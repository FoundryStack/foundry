defmodule Foundry.Chat.ToolLoop do
  @moduledoc """
  Agentic tool-calling loop for API-based LLM providers.

  Calls Gemini's generateContent API with tool definitions, executes any tool
  calls in the response, appends results to the conversation, and repeats until
  the model returns final text with no pending tool calls.
  """

  require Logger

  @default_max_iterations 15

  @doc """
  Runs the agentic loop with an LLM provider.

  Accepts messages and opts, calls the provider with tool definitions,
  handles tool execution, and yields events to the on_event callback.

  Events:
    * `{:delta, text}` — newly streamed assistant text
    * `{:trace, event}` — tool call execution trace
    * `{:result, text, metadata}` — final response
  """
  def run(messages, opts, on_event) when is_function(on_event, 1) do
    api_key = Keyword.get(opts, :api_key)
    model = Keyword.get(opts, :model)
    project_root = Keyword.get(opts, :project_root)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    timeout_ms = Keyword.get(opts, :timeout_ms, 120_000)
    system_prompt = Keyword.get(opts, :system_prompt)

    tool_schemas = Foundry.Chat.ShellTools.all()
    gemini_messages = convert_messages(messages)

    run_loop(
      gemini_messages,
      %{
        api_key: api_key,
        model: model,
        project_root: project_root,
        timeout_ms: timeout_ms,
        system_prompt: system_prompt,
        tool_schemas: tool_schemas,
        iterations: 0,
        max_iterations: max_iterations,
        on_event: on_event
      }
    )
  end

  defp run_loop(messages, state) do
    %{
      api_key: api_key,
      model: model,
      system_prompt: system_prompt,
      tool_schemas: tool_schemas,
      iterations: iterations,
      max_iterations: max_iterations,
      on_event: on_event,
      project_root: project_root
    } = state

    if iterations >= max_iterations do
      {:error, {:max_iterations_exceeded, max_iterations}}
    else
      case call_gemini_with_tools(messages, system_prompt, tool_schemas, model, api_key, on_event) do
        {:ok, content, true} ->
          tool_calls = extract_tool_calls(content)
          text = extract_text_from_content(content)
          tool_names = Enum.map(tool_calls, &(&1["name"]))
          Logger.info("Gemini response: iteration=#{iterations}, tool_calls=#{inspect(tool_names)}, text_length=#{String.length(text)}")

          if text != "" do
            on_event.({:delta, text})
          end

          {tool_results, updated_messages} =
            execute_tool_calls(tool_calls, messages, content, project_root, on_event)

          if tool_results == [] or length(tool_calls) == 0 do
            # No tool calls actually executed despite has_tool_calls=true
            Logger.info("No tool calls executed, ending loop at iteration #{iterations}")
            on_event.({:result, text, %{}})
            {:ok, text, %{}}
          else
            Logger.info("Executed #{length(tool_results)} tools, looping to iteration #{iterations + 1}")
            run_loop(updated_messages, %{state | iterations: iterations + 1})
          end

        {:ok, content, false} ->
          text = extract_text_from_content(content)
          Logger.info("Gemini response: has_tool_calls=false, text_length=#{String.length(text)}")
          if text != "" do
            on_event.({:delta, text})
          end
          on_event.({:result, text, %{}})
          {:ok, text, %{}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    e ->
      Logger.error("Tool loop error: #{inspect(e)}")
      {:error, {:tool_loop_error, Exception.message(e)}}
  end

  defp execute_tool_calls(tool_calls, messages, model_content, project_root, on_event) do
    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        name = tool_call["name"]
        args = tool_call["args"]
        id = tool_call["id"]

        Logger.info("Tool call: #{name} (id=#{id}) with args: #{inspect(args)}")
        on_event.({:trace, %{
          "provider" => "gemini",
          "type" => "tool.call",
          "item_type" => "tool_call",
          "tool" => name,
          "message" => "Tool call: #{name}",
          "item" => %{"name" => name, "args" => args, "id" => id}
        }})

        result =
          case Foundry.Chat.ShellTools.execute(name, args, project_root) do
            {:ok, output} ->
              Logger.info("Tool result: #{name} (id=#{id}) succeeded")
              on_event.({:trace, %{
                "provider" => "gemini",
                "type" => "tool.result",
                "item_type" => "tool_call",
                "tool" => name,
                "message" => "Tool completed: #{name}",
                "item" => %{"status" => "ok", "id" => id}
              }})
              %{"output" => output}

            {:error, reason} ->
              Logger.info("Tool result: #{name} (id=#{id}) failed: #{inspect(reason)}")
              on_event.({:trace, %{
                "provider" => "gemini",
                "type" => "tool.error",
                "item_type" => "tool_call",
                "tool" => name,
                "message" => "Tool failed: #{name}",
                "item" => %{"status" => "error", "reason" => inspect(reason), "id" => id}
              }})
              %{"error" => reason}
          end

        %{
          "functionResponse" => %{
            "name" => name,
            "response" => result,
            "id" => id
          }
        }
      end)

    model_turn = %{"role" => "model", "parts" => model_content["parts"]}
    tool_turn = %{"role" => "user", "parts" => tool_results}

    {tool_results, messages ++ [model_turn, tool_turn]}
  end

  defp call_gemini_with_tools(messages, system_prompt, tool_schemas, model, api_key, _on_event) do
    body = build_gemini_request(messages, system_prompt, tool_schemas)

    case Req.post(
      url: "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent",
      params: [key: api_key],
      headers: [{"content-type", "application/json"}],
      json: body,
      receive_timeout: 60_000,
      retry: false
    ) do
      {:ok, %Req.Response{status: 200, body: %{"candidates" => [candidate | _]}}} ->
        content = candidate["content"]
        has_tools = has_tool_calls(content)
        {:ok, content, has_tools}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Gemini error: #{status} - #{inspect(body)}")
        {:error, {:gemini_error, status}}

      {:error, reason} ->
        {:error, {:gemini_request_error, reason}}
    end
  end

  defp build_gemini_request(messages, system_prompt, tool_schemas) do
    body = %{
      "contents" => messages,
      "generationConfig" => %{"temperature" => 1.0},
      "tools" => [
        %{
          "functionDeclarations" => tool_schemas
        }
      ]
    }

    if system_prompt do
      Map.put(body, "systemInstruction", %{
        "parts" => [%{"text" => system_prompt}]
      })
    else
      body
    end
  end

  defp convert_messages(messages) do
    messages
    |> Enum.reject(&is_system_message?/1)
    |> Enum.map(&convert_message/1)
  end

  defp convert_message(%{"role" => role, "content" => content}) do
    %{
      "role" => if(role == "assistant", do: "model", else: "user"),
      "parts" => [%{"text" => content}]
    }
  end

  defp is_system_message?(%{"role" => "system"}), do: true
  defp is_system_message?(_), do: false

  defp extract_text_from_content(%{"parts" => parts}) when is_list(parts) do
    Enum.map_join(parts, "", fn part -> part["text"] || "" end)
  end

  defp extract_text_from_content(_), do: ""

  defp extract_tool_calls(%{"parts" => parts}) when is_list(parts) do
    parts
    |> Enum.filter(&Map.has_key?(&1, "functionCall"))
    |> Enum.map(& &1["functionCall"])
  end

  defp extract_tool_calls(_), do: []

  defp has_tool_calls(%{"parts" => parts}) when is_list(parts) do
    Enum.any?(parts, &Map.has_key?(&1, "functionCall"))
  end

  defp has_tool_calls(_), do: false
end
