defmodule Foundry.GeminiProvider do
  @moduledoc """
  Google Gemini API streaming provider.

  Uses the generativelanguage.googleapis.com API with streaming support.
  Requires GEMINI_API_KEY environment variable or :api_key in opts.
  """

  @default_base_url "https://generativelanguage.googleapis.com/v1beta"
  @default_model "gemini-2.0-flash"
  @default_timeout_ms 120_000

  @doc """
  Lists available Gemini models that support streaming.
  """
  def list_models(opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("GEMINI_API_KEY")
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

    if api_key do
      case Req.get(
        url: models_url(base_url),
        params: [key: api_key],
        receive_timeout: timeout_ms,
        retry: false
      ) do
        {:ok, %Req.Response{status: status, body: %{"models" => models}}} when status in 200..299 ->
          streaming_models =
            models
            |> Enum.filter(&is_streaming_capable?/1)
            |> Enum.map(& &1["name"])
            |> Enum.map(&extract_model_id/1)
            |> Enum.filter(&is_binary/1)

          {:ok, streaming_models}

        {:ok, %Req.Response{status: 401}} ->
          {:error, {:gemini_auth_error, "Invalid GEMINI_API_KEY"}}

        {:ok, %Req.Response{status: 429}} ->
          {:error, {:gemini_quota_error, "Rate limited or quota exceeded"}}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:gemini_http_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:gemini_no_api_key, "GEMINI_API_KEY not set"}}
    end
  end

  @doc """
  Streams a conversation through Gemini.

  Events:

    * `{:delta, text}` — newly streamed assistant text
    * `{:trace, event}` — tool call execution trace
    * `{:result, text, metadata}` — final successful response
  """
  def stream(messages, opts \\ [], on_event) when is_function(on_event, 1) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("GEMINI_API_KEY")
    model = Keyword.get(opts, :model, @default_model)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    system_prompt = Keyword.get(opts, :system_prompt)
    project_root = Keyword.get(opts, :project_root)

    if api_key do
      model_id = extract_model_id(model)

      tool_loop_opts = [
        api_key: api_key,
        model: model_id,
        system_prompt: system_prompt,
        timeout_ms: timeout_ms,
        project_root: project_root
      ]

      Foundry.Chat.ToolLoop.run(messages, tool_loop_opts, on_event)
    else
      {:error, {:gemini_no_api_key, "GEMINI_API_KEY not set"}}
    end
  end


  defp models_url(base_url) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>("/models")
  end

  defp is_streaming_capable?(%{"name" => name}) when is_binary(name) do
    not String.contains?(name, ["test", "paligemma"])
  end

  defp is_streaming_capable?(_), do: false

  defp extract_model_id("models/" <> id), do: id
  defp extract_model_id(id), do: id
end
