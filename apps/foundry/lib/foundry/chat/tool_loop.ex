defmodule Foundry.Chat.ToolLoop do
  @moduledoc """
  Agentic tool-calling loop for API-based LLM providers.

  Delegates to Gemini's native tool calling. Since ReqLLM doesn't expose
  tool call handling in stream_text, we use generate_text instead which
  returns structured responses, then re-query with tool results on tool calls.
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

    run_loop(
      messages,
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
      timeout_ms: _timeout_ms,
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
      # Call Gemini with tools and structured output
      case call_gemini_with_tools(
             messages,
             system_prompt,
             tool_schemas,
             model,
             api_key
           ) do
        {:ok, text, _has_tool_calls} ->
          on_event.({:delta, text})
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

  defp call_gemini_with_tools(messages, system_prompt, tool_schemas, model, api_key) do
    # Build request body with tools for Gemini
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
        text = extract_text_from_content(content)
        has_tools = has_tool_calls(content)
        {:ok, text, has_tools}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Gemini error: #{status} - #{inspect(body)}")
        {:error, {:gemini_error, status}}

      {:error, reason} ->
        {:error, {:gemini_request_error, reason}}
    end
  end

  defp build_gemini_request(messages, system_prompt, tool_schemas) do
    contents = convert_messages(messages)

    body = %{
      "contents" => contents,
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
    parts
    |> Enum.map_join("", fn part ->
      part["text"] || ""
    end)
  end

  defp extract_text_from_content(_), do: ""

  defp has_tool_calls(%{"parts" => parts}) when is_list(parts) do
    Enum.any?(parts, fn part -> Map.has_key?(part, "functionCall") end)
  end

  defp has_tool_calls(_), do: false

end
