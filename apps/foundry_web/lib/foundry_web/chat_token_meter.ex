defmodule FoundryWeb.ChatTokenMeter do
  @moduledoc """
  Calculates and formats the chat token usage meter shown in the input toolbar.

  Produces a meter map consumed by the token-meter UI button and its tooltip.
  """

  alias FoundryWeb.ChatModelCatalog

  @type meter :: %{
          provider: atom() | String.t() | nil,
          model: String.t() | nil,
          exact_total: integer() | nil,
          estimate_total: integer(),
          total: integer(),
          window: integer() | nil,
          ratio: float() | nil
        }

  @doc """
  Builds a token meter from current session state.
  """
  @spec build([map()], map(), String.t(), map()) :: meter()
  def build(messages, session_digest, input, llm_diagnostics) do
    diagnostics = llm_diagnostics || %{}
    model = diagnostics[:model] || diagnostics["model"]
    provider = diagnostics[:provider] || diagnostics["provider"]

    exact_usage = Map.get(session_digest || %{}, "recent_token_usage", %{})
    exact_total = exact_usage[:total_tokens] || exact_usage["total_tokens"]

    selected_model = resolve_model_entry(provider, model)
    window = selected_model && selected_model.context_window

    estimate = estimate_tokens(messages, session_digest, input)
    total = exact_total || estimate
    ratio = if is_integer(window) and window > 0, do: min(total / window, 1.0), else: nil

    %{
      provider: provider,
      model: model,
      exact_total: exact_total,
      estimate_total: estimate,
      total: total,
      window: window,
      ratio: ratio
    }
  end

  @doc """
  CSS `style` attribute for the conic-gradient progress ring.
  """
  def ring_style(%{ratio: ratio}) when is_number(ratio) do
    angle = Float.round(ratio * 360.0, 2)

    "background: conic-gradient(color-mix(in oklch, var(--color-primary) 78%, white) #{angle}deg, color-mix(in oklch, var(--color-base-300) 88%, transparent) #{angle}deg);"
  end

  def ring_style(_meter) do
    "background: color-mix(in oklch, var(--color-base-300) 72%, transparent);"
  end

  @doc """
  Short label shown inside the ring button (e.g. "42%").
  """
  def ring_label(%{ratio: ratio}) when is_number(ratio), do: "#{round(ratio * 100)}%"
  def ring_label(_meter), do: "?"

  @doc """
  One-line summary for the tooltip header (e.g. "42K / 200K").
  """
  def summary(%{total: total, window: window})
       when is_integer(total) and is_integer(window) do
    "#{format_compact(total)} / #{format_compact(window)}"
  end

  def summary(%{estimate_total: total, window: nil}) when is_integer(total) do
    "~#{format_compact(total)} • window unknown"
  end

  def summary(_meter), do: "window unknown"

  @doc """
  Full tooltip title string.
  """
  def title(%{total: total, exact_total: exact, window: window, model: model}) do
    usage =
      cond do
        is_integer(exact) -> "#{exact} exact tokens from provider"
        is_integer(total) -> "~#{total} estimated tokens"
        true -> "Token usage unavailable"
      end

    window_text = if is_integer(window), do: "window #{window}", else: "window unknown"

    [usage, window_text, model || "model unknown"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" • ")
  end

  @doc """
  Formats token usage breakdown from a session digest entry.
  """
  def usage_label(usage) do
    usage = usage || %{}
    total = usage[:total_tokens] || usage["total_tokens"]
    input = usage[:input_tokens] || usage["input_tokens"]
    output = usage[:output_tokens] || usage["output_tokens"]

    cond do
      is_integer(total) and is_integer(input) and is_integer(output) ->
        "#{total} total • #{input} in • #{output} out"

      is_integer(total) ->
        "#{total} tokens"

      is_integer(input) or is_integer(output) ->
        "#{input || 0} in • #{output || 0} out"

      true ->
        "tokens unavailable"
    end
  end

  # --- Private ---

  defp estimate_tokens(messages, session_digest, input) do
    parts = [
      Map.get(session_digest || %{}, "working_summary", ""),
      Jason.encode!(session_digest || %{}),
      Enum.map_join(messages || [], "\n", &"#{&1["role"]}: #{&1["content"] || ""}"),
      input || ""
    ]

    parts
    |> Enum.join("\n")
    |> String.length()
    |> Kernel./(4)
    |> Float.ceil()
    |> trunc()
    |> Kernel.+(400)
  end

  defp resolve_model_entry(provider, model_id) when is_binary(model_id) do
    catalog = ChatModelCatalog.catalog()
    id = "#{provider}:#{model_id}"
    ChatModelCatalog.get(catalog, id)
  end

  defp resolve_model_entry(_provider, _model), do: nil

  defp format_compact(value) when is_integer(value) and value >= 1_000_000,
    do: "#{Float.round(value / 1_000_000, 1)}M"

  defp format_compact(value) when is_integer(value) and value >= 1000,
    do: "#{Float.round(value / 1000, 1)}K"

  defp format_compact(value) when is_integer(value), do: Integer.to_string(value)
end
