defmodule Foundry.Chat.ToolLoop do
  @moduledoc """
  Agentic tool-calling loop using ReqLLM for streaming.

  Uses ReqLLM.stream_text/3 with the Google provider to handle Gemini streaming
  correctly. Tool calls are detected via ReqLLM.StreamChunk, executed, and
  results fed back as tool messages.
  """

  require Logger

  @default_max_iterations 50

  @doc """
  Runs the agentic loop with Gemini via ReqLLM.

  Accepts messages and opts, streams from Gemini with tool definitions,
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
    system_prompt = Keyword.get(opts, :system_prompt)

    req_llm_messages = convert_messages(messages)
    req_llm_tools = build_req_llm_tools(project_root)

    run_loop(
      req_llm_messages,
      %{
        api_key: api_key,
        model: model,
        project_root: project_root,
        system_prompt: system_prompt,
        tools: req_llm_tools,
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
      tools: tools,
      iterations: iterations,
      max_iterations: max_iterations,
      on_event: on_event,
      project_root: project_root
    } = state

    if iterations >= max_iterations do
      {:error, {:max_iterations_exceeded, max_iterations}}
    else
      case stream_from_gemini(messages, system_prompt, tools, model, api_key, on_event) do
        {:ok, {tool_calls, text}} ->
          Logger.info("Gemini response: iteration=#{iterations}, tool_calls=#{length(tool_calls)}, text_length=#{String.length(text)}")

          if tool_calls == [] do
            on_event.({:result, text, %{}})
            {:ok, text, %{}}
          else
            execute_and_continue(
              tool_calls,
              text,
              messages,
              state,
              iterations,
              on_event,
              project_root
            )
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    e ->
      Logger.error("Tool loop error: #{inspect(e)}")
      {:error, {:tool_loop_error, Exception.message(e)}}
  end

  defp execute_and_continue(tool_calls, text, messages, state, iterations, on_event, project_root) do
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
              output

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
              "Error: #{inspect(reason)}"
          end

        %ReqLLM.Message{
          role: :tool,
          content: [%ReqLLM.Message.ContentPart{type: :text, text: result}],
          tool_call_id: id,
          name: name
        }
      end)

    req_llm_tool_calls =
      Enum.map(tool_calls, fn tc ->
        %ReqLLM.ToolCall{
          id: tc["id"],
          type: "function",
          function: %{
            "name" => tc["name"],
            "arguments" => tc["args"]
          }
        }
      end)

    assistant_turn = %ReqLLM.Message{
      role: :assistant,
      content: [%ReqLLM.Message.ContentPart{type: :text, text: text}],
      tool_calls: req_llm_tool_calls
    }

    updated_messages = messages ++ [assistant_turn] ++ tool_results

    Logger.info("Executed #{length(tool_results)} tools, looping to iteration #{iterations + 1}")
    run_loop(updated_messages, %{state | iterations: iterations + 1})
  end

  defp stream_from_gemini(messages, system_prompt, tools, model, api_key, on_event) do
    case ReqLLM.stream_text(
      "google:#{model}",
      messages,
      tools: tools,
      system_prompt: system_prompt,
      api_key: api_key
    ) do
      {:ok, stream_response} ->
        {tool_calls, text} =
          Enum.reduce(stream_response.stream, {[], ""}, fn chunk, {calls, acc_text} ->
            case chunk.type do
              :content ->
                on_event.({:delta, chunk.text})
                {calls, acc_text <> chunk.text}

              :tool_call ->
                call_id = chunk.metadata[:id] || "call_#{System.unique_integer([:positive])}"
                call = %{
                  "name" => chunk.name,
                  "args" => chunk.arguments,
                  "id" => call_id
                }
                {calls ++ [call], acc_text}

              _ ->
                {calls, acc_text}
            end
          end)

        {:ok, {tool_calls, text}}

      {:error, reason} ->
        Logger.error("ReqLLM streaming failed: #{inspect(reason)}")
        {:error, {:req_llm_error, reason}}
    end
  end

  defp build_req_llm_tools(project_root) do
    Foundry.Chat.ShellTools.all()
    |> Enum.map(fn schema ->
      ReqLLM.Tool.new!(
        name: schema["name"],
        description: schema["description"],
        parameter_schema: schema["parameters"],
        callback: fn args ->
          Foundry.Chat.ShellTools.execute(schema["name"], args, project_root)
        end
      )
    end)
  end

  defp convert_messages(messages) do
    messages
    |> Enum.reject(&is_system_message?/1)
    |> Enum.map(&convert_message/1)
  end

  defp convert_message(%{"role" => role, "content" => content}) do
    %{
      "role" => if(role == "assistant", do: "assistant", else: "user"),
      "content" => content
    }
  end

  defp is_system_message?(%{"role" => "system"}), do: true
  defp is_system_message?(_), do: false
end
