defmodule PhoenixLLMChat.StreamRuntime do
  @moduledoc """
  Manages async task lifecycle for streaming LLM responses.

  Handles:
  - Task spawning and reference correlation
  - Streaming event accumulation (:delta, :done, :error)
  - Provider trace events
  - Task process death cleanup
  - Response finalization
  """

  import Phoenix.Component, only: [assign: 3]
  require Logger

  def handle_llm_delta(socket, _request_ref, delta) do
    current_response = socket.assigns.response || ""
    new_response = current_response <> delta

    socket
    |> assign(:response, new_response)
    |> maybe_push_response_delta(delta)
  end

  def handle_llm_done(socket, _request_ref, metadata \\ %{}) do
    response = socket.assigns.response || ""

    socket
    |> assign(:loading, false)
    |> assign(:current_request_ref, nil)
    |> finalize_response(response, metadata)
  end

  def handle_llm_error(socket, _request_ref, error) do
    Logger.error("LLM stream error: #{inspect(error)}")

    error_message = format_error(error)

    socket
    |> assign(:loading, false)
    |> assign(:error, error_message)
    |> assign(:current_request_ref, nil)
  end

  def handle_llm_trace(socket, _request_ref, trace_event) do
    traces = socket.assigns[:traces] || []
    assign(socket, :traces, [trace_event | traces])
end

  def handle_task_ref_cleanup(socket, {_ref, _result}) do
    # Task completed normally - ref already cleaned up by :done handler
    socket
  end

  def handle_process_down(socket, {_down, ref, :process, _pid, reason}) do
    Logger.warning("Task process died: ref=#{inspect(ref)}, reason=#{inspect(reason)}")
    current_ref = socket.assigns[:current_request_ref]

    if current_ref == ref do
      socket
      |> assign(:loading, false)
      |> assign(:current_request_ref, nil)
      |> assign(:error, "Task interrupted")
    else
      socket
    end
  end

  def cleanup_on_terminate(socket) do
    # Kill any active task on session close
    case socket.assigns[:current_request_ref] do
      nil -> :ok
      ref -> Process.demonitor(ref, [:flush])
    end
  end

  defp maybe_push_response_delta(socket, delta) do
    # Hook point for UI updates during streaming
    Phoenix.LiveView.push_event(socket, "response_delta", %{delta: delta})
  end

  defp finalize_response(socket, response, _metadata) do
    # Hook point for post-processing (filters, formatting, persistence)
    Phoenix.LiveView.push_event(socket, "response_done", %{response: response})
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
