defmodule PhoenixLLMChat.Core do
  @moduledoc """
  Core event handling for chat flow.

  Manages:
  - Message input and chat submission
  - View state switching
  - Message lifecycle (send, receive, persist)
  - Response finalization and formatting
  """

  require Logger
  alias PhoenixLLMChat.{StreamRuntime, LLMContext, Utilities}

  def mount(socket, session) do
    socket
    |> Phoenix.Component.assign(:messages, [])
    |> Phoenix.Component.assign(:input, "")
    |> Phoenix.Component.assign(:chat_loading, false)
    |> Phoenix.Component.assign(:error, nil)
    |> Phoenix.Component.assign(:response, nil)
    |> Phoenix.Component.assign(:current_request_ref, nil)
    |> Phoenix.Component.assign(:session_id, session["session_id"] || generate_session_id())
  end

  def handle_event("update_chat_input", %{"value" => value}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :input, value)}
  end

  def handle_event("send_message", _params, socket) do
    input = socket.assigns.input
    session_id = socket.assigns.session_id

    case String.trim(input) do
      "" ->
        {:noreply, socket}

      trimmed_input ->
        socket
        |> add_message(%{"role" => "user", "content" => trimmed_input, "session_id" => session_id})
        |> Phoenix.Component.assign(:input, "")
        |> Phoenix.Component.assign(:chat_loading, true)
        |> Phoenix.Component.assign(:response, nil)
        |> Phoenix.Component.assign(:error, nil)
        |> submit_to_llm(trimmed_input)
        |> case do
          {:ok, updated_socket} -> {:noreply, updated_socket}
          {:error, reason} ->
            {:noreply, Phoenix.Component.assign(socket, :error, "Failed to send: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("set_chat_view", %{"view" => view}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :current_view, view)}
  end

  def handle_event("clear_chat", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :messages, [])}
  end

  def handle_info({:llm_stream_delta, request_ref, delta}, socket) do
    case socket.assigns[:current_request_ref] do
      ^request_ref -> {:noreply, StreamRuntime.handle_llm_delta(socket, request_ref, delta)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_done, request_ref, metadata}, socket) do
    case socket.assigns[:current_request_ref] do
      ^request_ref -> {:noreply, finalize_response(socket, request_ref, metadata)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_error, request_ref, error}, socket) do
    case socket.assigns[:current_request_ref] do
      ^request_ref -> {:noreply, StreamRuntime.handle_llm_error(socket, request_ref, error)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:llm_stream_trace, request_ref, trace}, socket) do
    case socket.assigns[:current_request_ref] do
      ^request_ref -> {:noreply, StreamRuntime.handle_llm_trace(socket, request_ref, trace)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    {:noreply, StreamRuntime.handle_task_ref_cleanup(socket, {ref, result})}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    {:noreply, StreamRuntime.handle_process_down(socket, {:DOWN, ref, :process, nil, nil})}
  end

  def terminate(_reason, socket) do
    StreamRuntime.cleanup_on_terminate(socket)
  end

  defp add_message(socket, message) do
    messages = socket.assigns.messages || []
    Phoenix.Component.assign(socket, :messages, messages ++ [message])
  end

  defp submit_to_llm(socket, user_message) do
    case LLMContext.call_llm(socket, user_message) do
      {:ok, updated_socket} -> {:ok, updated_socket}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_response(socket, request_ref, metadata) do
    response = socket.assigns.response || ""

    socket
    |> add_message(%{
      "role" => "assistant",
      "content" => response,
      "request_ref" => request_ref,
      "metadata" => metadata
    })
    |> apply_message_filters(response)
    |> StreamRuntime.handle_llm_done(request_ref, metadata)
  end

  defp apply_message_filters(socket, response) do
    case Application.get_env(:phoenix_llm_chat, :response_filters) do
      nil -> socket
      filters -> Phoenix.Component.assign(socket, :response, Utilities.apply_message_filters(response, filters))
    end
  end

  defp generate_session_id do
    Base.encode16(:crypto.strong_rand_bytes(8))
  end
end
