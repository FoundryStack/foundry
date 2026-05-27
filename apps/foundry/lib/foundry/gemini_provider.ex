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
    * `{:result, text, metadata}` — final successful response
  """
  def stream(messages, opts \\ [], on_event) when is_function(on_event, 1) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("GEMINI_API_KEY")
    model = Keyword.get(opts, :model, @default_model)
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    system_prompt = Keyword.get(opts, :system_prompt)

    if api_key do
      model_id = extract_model_id(model)

      request = [
        url: completion_url(base_url, model_id),
        params: [key: api_key, alt: "sse"],
        headers: [{"content-type", "application/json"}],
        json: build_request_body(messages, system_prompt),
        receive_timeout: timeout_ms,
        retry: false,
        into: :self
      ]

      with {:ok, response} <- Req.post(request),
           :ok <- ensure_success(response) do
        collect_stream(response, "", [], timeout_ms, on_event)
      else
        {:error, %Req.TransportError{reason: :econnrefused}} ->
          {:error, {:gemini_unavailable, base_url}}

        {:error, %Req.TransportError{} = error} ->
          {:error, {:gemini_transport_error, Exception.message(error)}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:gemini_no_api_key, "GEMINI_API_KEY not set"}}
    end
  end

  defp build_request_body(messages, system_prompt) do
    contents = convert_messages(messages)

    body = %{
      "contents" => contents,
      "generationConfig" => %{
        "temperature" => 1.0
      }
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
      "role" => map_role(role),
      "parts" => [%{"text" => content}]
    }
  end

  defp map_role("user"), do: "user"
  defp map_role("assistant"), do: "model"
  defp map_role(other), do: other

  defp is_system_message?(%{"role" => "system"}), do: true
  defp is_system_message?(_), do: false

  defp completion_url(base_url, model_id) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>("/models/#{model_id}:streamGenerateContent")
  end

  defp models_url(base_url) do
    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>("/models")
  end

  defp ensure_success(%Req.Response{status: status}) when status in 200..299, do: :ok

  defp ensure_success(%Req.Response{status: status, body: body}) do
    {:error, {:gemini_http_error, status, body}}
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
            {:error, {:gemini_stream_error, reason}}

          other ->
            {:error, {:gemini_stream_error, {:unexpected_message, other}}}
        end
    after
      timeout_ms ->
        partial = IO.iodata_to_binary(chunks)
        {:error, {:timeout, partial}}
    end
  end

  defp parse_sse(data) do
    # Split on double newlines to separate complete SSE events
    parts = String.split(data, "\n\n")

    if Enum.count(parts) == 1 do
      # No double newline found - might be incomplete or single complete event
      # Extract complete data lines and keep unparseable remainder as buffer
      data_lines =
        data
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "data:"))
        |> Enum.map(&(String.trim_leading(&1, "data:") |> String.trim()))

      # Process all found data lines, buffer is now empty since we extracted them
      Enum.reduce(data_lines, {"", [], false}, &parse_data_line/2)
    else
      # Multiple parts - last is buffer, rest are complete events
      {events, [buffer]} = Enum.split(parts, -1)

      Enum.reduce(events, {buffer, [], false}, fn event, {_buf, chunks, done?} ->
        data_lines =
          event
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&String.starts_with?(&1, "data:"))
          |> Enum.map(&(String.trim_leading(&1, "data:") |> String.trim()))

        Enum.reduce(data_lines, {buffer, chunks, done?}, &parse_data_line/2)
      end)
    end
  end

  defp parse_data_line(json, {buffer, chunks, done?}) do
    case Jason.decode(json) do
      {:ok, %{"candidates" => [candidate | _]}} when is_map(candidate) ->
        # Extract text if present
        {chunks, done?} =
          case candidate do
            %{"content" => %{"parts" => parts}} when is_list(parts) ->
              text =
                parts
                |> Enum.map_join("", fn part ->
                  part["text"] || ""
                end)

              if text == "" do
                {chunks, done?}
              else
                {chunks ++ [text], done?}
              end

            _ ->
              {chunks, done?}
          end

        # Check if finished
        done? =
          if is_map(candidate) and Map.has_key?(candidate, "finishReason") do
            true
          else
            done?
          end

        {buffer, chunks, done?}

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

  defp is_streaming_capable?(%{"name" => name}) when is_binary(name) do
    # Gemini API supports streaming via alt=sse for models with generateContent support
    # Filter out test/old models
    not String.contains?(name, ["test", "paligemma"])
  end

  defp is_streaming_capable?(_), do: false

  defp extract_model_id("models/" <> id), do: id
  defp extract_model_id(id), do: id
end
