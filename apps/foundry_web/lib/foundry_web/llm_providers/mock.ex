defmodule FoundryWeb.LLMProviders.Mock do
  @moduledoc """
  Mock LLM provider for testing. Returns a canned response without calling any external API.
  """

  require Logger

  def stream(messages, opts \\ []) when is_list(messages) do
    response = Keyword.get(opts, :response, generate_default_response(messages))
    delay_ms = Keyword.get(opts, :delay_ms, 10)

    Stream.resource(
      fn ->
        Logger.info("Mock LLM stream starting with response: #{String.slice(response, 0, 100)}...")
        String.split(response, ~r/(\s+)/, include_captures: true)
      end,
      fn
        [] ->
          {:halt, nil}

        [word | rest] ->
          Process.sleep(delay_ms)
          {{:delta, word}, rest}
      end,
      fn _ ->
        Logger.info("Mock LLM stream completed")
        :ok
      end
    )
  end

  defp generate_default_response(_messages) do
    "This is a mock LLM response. " <>
      "In a real scenario, this would be a response from the Anthropic Claude API. " <>
      "For testing purposes, this mock provider allows verifying the chat streaming flow without requiring API keys or network access."
  end
end
