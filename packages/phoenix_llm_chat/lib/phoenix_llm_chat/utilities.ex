defmodule PhoenixLLMChat.Utilities do
  @moduledoc """
  Generic utilities for response formatting, filtering, and error handling.
  """

  def summarize_response(response) when is_binary(response) do
    String.slice(response, 0..100) <> "..."
  end

  def summarize_response(response), do: inspect(response)

  def normalize_usage(%{"input_tokens" => in_t, "output_tokens" => out_t} = usage) do
    %{
      input_tokens: in_t,
      output_tokens: out_t,
      total_tokens: in_t + out_t,
      raw: usage
    }
  end

  def normalize_usage(usage) when is_map(usage) do
    # Flexible normalization for different provider formats
    %{
      input_tokens: usage["input_tokens"] || usage[:input_tokens] || 0,
      output_tokens: usage["output_tokens"] || usage[:output_tokens] || 0,
      raw: usage
    }
  end

  def normalize_usage(nil), do: nil
  def normalize_usage(_), do: nil

  def usage_total(%{input_tokens: in_t, output_tokens: out_t}) do
    in_t + out_t
  end

  def usage_total(_), do: 0

  def format_error(error) when is_binary(error), do: error

  def format_error({:error, reason}) do
    format_error(reason)
  end

  def format_error(%{"error" => msg}) when is_binary(msg), do: msg

  def format_error(error) do
    inspect(error)
  end

  def apply_message_filters(message, filters \\ []) do
    Enum.reduce(filters, message, fn filter_fn, msg ->
      filter_fn.(msg)
    end)
  end

  def filter_response(response, filter_type, options \\ []) do
    case filter_type do
      :truncate ->
        max_len = options[:max_length] || 2000
        String.slice(response, 0..max_len)

      :strip_markdown ->
        strip_markdown_markers(response)

      :custom ->
        case options[:handler] do
          nil -> response
          handler -> handler.(response)
        end

      _ ->
        response
    end
  end

  def maybe_filter_response(response, filter_config) when is_nil(filter_config) do
    response
  end

  def maybe_filter_response(response, filters) when is_list(filters) do
    Enum.reduce(filters, response, fn filter, acc ->
      filter_response(acc, filter)
    end)
  end

  def maybe_filter_response(response, filter_type) do
    filter_response(response, filter_type)
  end

  defp strip_markdown_markers(text) do
    text
    |> String.replace(~r/^#+\s+/m, "")
    |> String.replace(~r/`{3}[\w]*\n/, "")
    |> String.replace(~r/`{3}\n/, "")
    |> String.replace(~r/\*\*(.*?)\*\*/s, "\\1")
    |> String.replace(~r/\*(.*?)\*/s, "\\1")
  end
end
