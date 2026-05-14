defmodule PhoenixLLMChat.TestHelpers do
  @moduledoc """
  Test helpers for PhoenixLLMChat testing.
  """

  def build_socket(assigns \\ %{}) do
    base = %{
      __changed__: nil,
      assigns: %{
        messages: [],
        input: "",
        loading: false,
        error: nil,
        response: nil,
        current_request_ref: nil,
        session_id: "test-session-#{Enum.random(1..1000)}"
      },
      private: %{},
      transport_pid: self()
    }

    updated_assigns = Map.merge(base.assigns, assigns)
    Map.put(base, :assigns, updated_assigns)
  end

  def configure_mock_provider(opts \\ []) do
    response = opts[:response] || "Hello world"
    delay_ms = opts[:delay_ms] || 10

    hook_fn = fn _provider, _socket, _messages, _opts ->
      ref = make_ref()
      spawn(fn ->
        words = String.split(response, " ")
        Enum.each(words, fn word ->
          Process.sleep(delay_ms)
          send(self(), {:llm_stream_delta, ref, word <> " "})
        end)
        send(self(), {:llm_stream_done, ref, %{"usage" => %{"input_tokens" => 10, "output_tokens" => length(words)}}})
      end)
      {:ok, ref}
    end

    Application.put_env(:phoenix_llm_chat, :hooks, %{
      call_llm_stream: hook_fn
    })
  end
end
