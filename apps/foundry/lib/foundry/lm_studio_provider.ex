defmodule Foundry.LMStudioProvider do
  @moduledoc """
  Local OpenAI-compatible chat provider for LM Studio.

  LM Studio exposes `/v1/chat/completions`; this module uses that API directly
  so local chat does not depend on hosted provider API keys or Claude Code usage.
  """

  @default_base_url "http://localhost:1234/v1"
  @default_model "local-model"
  @default_timeout_ms 120_000

  @doc """
  Streams a conversation through LM Studio.

  Events:

    * `{:delta, text}` — newly streamed assistant text
    * `{:result, text, metadata}` — final successful response
  """
  def stream(messages, opts \\ [], on_event) when is_function(on_event, 1) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    model = Keyword.get(opts, :model, @default_model)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    request = [
      url: completion_url(base_url),
      headers: [
        {"authorization", "Bearer #{Keyword.get(opts, :api_key, "lm-studio")}"},
        {"content-type", "application/json"},
        {"accept", "text/event-stream"}
      ],
      json: %{
        model: model,
        messages: messages,
        stream: true,
        temperature: Keyword.get(opts, :temperature, 0.2)
      },
      receive_timeout: timeout_ms,
      retry: false,
      into: :self
    ]

    with {:ok, response} <- Req.post(request),
         :ok <- ensure_success(response) do
      collect_stream(response, "", [], timeout_ms, on_event)
    else
      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, {:lm_studio_unavailable, base_url}}

      {:error, %Req.TransportError{} = error} ->
        {:error, {:lm_studio_transport_error, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp completion_url(base_url) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>("/chat/completions")
  end

  defp ensure_success(%Req.Response{status: status}) when status in 200..299, do: :ok

  defp ensure_success(%Req.Response{status: status, body: body}) do
    {:error, {:lm_studio_http_error, status, body}}
  end

  defp collect_stream(response, buffer, chunks, timeout_ms, on_event) do
    receive do
      message ->
        case Req.parse_message(response, message) do
          {:ok, [data: data]} ->
            {next_buffer, new_chunks, done?} = parse_sse(buffer <> data)

            Enum.each(new_chunks, fn chunk -> on_event.({:delta, chunk}) end)

            chunks = chunks ++ new_chunks

            if done? do
              finish(chunks, on_event)
            else
              collect_stream(response, next_buffer, chunks, timeout_ms, on_event)
            end

          {:ok, [:done]} ->
            finish(chunks, on_event)

          {:error, reason} ->
            {:error, {:lm_studio_stream_error, reason}}
        end
    after
      timeout_ms ->
        partial = IO.iodata_to_binary(chunks)
        {:error, {:timeout, partial}}
    end
  end

  defp parse_sse(data) do
    parts = String.split(data, "\n\n")
    {events, [buffer]} = Enum.split(parts, -1)

    Enum.reduce(events, {buffer, [], false}, fn event, {buffer, chunks, done?} ->
      event
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&(String.trim_leading(&1, "data:") |> String.trim()))
      |> Enum.reduce({buffer, chunks, done?}, &parse_data_line/2)
    end)
  end

  defp parse_data_line("[DONE]", {buffer, chunks, _done?}), do: {buffer, chunks, true}

  defp parse_data_line(json, {buffer, chunks, done?}) do
    case Jason.decode(json) do
      {:ok, %{"choices" => choices}} when is_list(choices) ->
        text =
          choices
          |> Enum.map_join("", fn choice ->
            get_in(choice, ["delta", "content"]) ||
              get_in(choice, ["message", "content"]) ||
              ""
          end)

        if text == "" do
          {buffer, chunks, done?}
        else
          {buffer, chunks ++ [text], done?}
        end

      _ ->
        {buffer, chunks, done?}
    end
  end

  defp finish(chunks, on_event) do
    text = IO.iodata_to_binary(chunks)
    metadata = %{}
    on_event.({:result, text, metadata})
    {:ok, text, metadata}
  end
end
