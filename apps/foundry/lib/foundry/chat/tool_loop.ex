defmodule Foundry.Chat.ToolLoop do
  @moduledoc """
  Agentic tool-calling loop for API-based LLM providers.

  Calls Gemini's generateContent API with tool definitions, executes any tool
  calls in the response, appends results to the conversation, and repeats until
  the model returns final text with no pending tool calls.
  """

  require Logger

  @default_max_iterations 10

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

          {tool_results, updated_messages} =
            execute_tool_calls(tool_calls, messages, content, project_root, on_event)

          if tool_results == [] do
            # No tool calls actually executed despite has_tool_calls=true
            on_event.({:result, text, %{}})
            {:ok, text, %{}}
          else
            run_loop(updated_messages, %{state | iterations: iterations + 1})
          end

        {:ok, content, false} ->
          text = extract_text_from_content(content)
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
      Enum.map(tool_calls, fn %{"name" => name, "args" => args} ->
        on_event.({:trace, {:tool_call, name, args}})

        result =
          case Foundry.Chat.ShellTools.execute(name, args, project_root) do
            {:ok, output} ->
              on_event.({:trace, {:tool_result, name, :ok}})
              %{"output" => output}

            {:error, reason} ->
              on_event.({:trace, {:tool_result, name, :error}})
              %{"error" => reason}
          end

        %{
          "functionResponse" => %{
            "name" => name,
            "response" => result
          }
        }
      end)

    model_turn = %{"role" => "model", "parts" => model_content["parts"]}
    tool_turn = %{"role" => "user", "parts" => tool_results}

    {tool_results, messages ++ [model_turn, tool_turn]}
  end

  defp call_gemini_with_tools(messages, system_prompt, tool_schemas, model, api_key, on_event) do
    body = build_gemini_request(messages, system_prompt, tool_schemas)

    request = [
      url: "https://generativelanguage.googleapis.com/v1beta/models/#{model}:streamGenerateContent",
      params: [key: api_key],
      headers: [
        {"content-type", "application/json"},
        {"accept", "text/event-stream"}
      ],
      json: body,
      receive_timeout: 60_000,
      retry: false,
      into: :self
    ]

    with {:ok, response} <- Req.post(request),
         {:ok, content, has_tools} <- collect_gemini_stream(response, "", nil, 60_000, on_event) do
      {:ok, content, has_tools}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_gemini_stream(response, buffer, last_content, timeout_ms, on_event) do
    receive do
      message ->
        case Req.parse_message(response, message) do
          {:ok, [data: data]} ->
            {next_buffer, last_content} = parse_gemini_sse(buffer <> data, last_content, on_event)
            collect_gemini_stream(response, next_buffer, last_content, timeout_ms, on_event)

          {:ok, [:done]} ->
            if last_content do
              has_tools = has_tool_calls(last_content)
              {:ok, last_content, has_tools}
            else
              {:error, {:gemini_stream_error, "No content received"}}
            end

          {:error, reason} ->
            {:error, {:gemini_stream_error, reason}}
        end
    after
      timeout_ms -> {:error, {:timeout, "Gemini stream timeout"}}
    end
  end

  defp parse_gemini_sse(data, last_content, on_event) do
    parts = String.split(data, "\n\n")
    {events, [buffer]} = Enum.split(parts, -1)

    final_content =
      Enum.reduce(events, last_content, fn event, acc ->
        event
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "data:"))
        |> Enum.map(&(String.trim_leading(&1, "data:") |> String.trim()))
        |> Enum.reduce(acc, fn json, content_acc ->
          parse_gemini_data_line(json, content_acc, on_event)
        end)
      end)

    {buffer, final_content}
  end

  defp parse_gemini_data_line(json, acc, on_event) do
    case Jason.decode(json) do
      {:ok, %{"candidates" => [%{"content" => content} | _]}} ->
        text = extract_text_from_content(content)
        if text != "" do
          on_event.({:delta, text})
        end
        content

      _ ->
        acc
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
