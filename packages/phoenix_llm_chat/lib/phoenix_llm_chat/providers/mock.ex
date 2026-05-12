defmodule PhoenixLLMChat.Providers.Mock do
  @moduledoc """
  Test provider that streams a canned response without calling any external API.
  Streams word-by-word with configurable delay so tests can verify delta events.
  """

  require Logger

  def stream(pid, _messages, opts \\ []) do
    response = opts[:response] || "This is a mock response."
    delay_ms = opts[:delay_ms] || 10

    ref = make_ref()

    Task.start(fn ->
      words = String.split(response, " ")
      Enum.each(words, fn word ->
        Process.sleep(delay_ms)
        send(pid, {:llm_stream_delta, ref, word <> " "})
      end)

      send(pid, {:llm_stream_done, ref, %{"usage" => %{"input_tokens" => 10, "output_tokens" => length(words)}}})
    end)

    {:ok, ref}
  end
end
