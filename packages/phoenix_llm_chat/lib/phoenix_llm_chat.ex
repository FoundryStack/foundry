defmodule PhoenixLLMChat do
  import Phoenix.Component, only: [assign: 3]

  @moduledoc """
  Generic streaming chat LiveView for Phoenix applications.

  Provides a complete chat interface with:
  - Multi-tab session management
  - Streaming LLM provider support
  - Async task orchestration
  - Extensible via hooks and behaviours

  ## Usage

  In your mount/3:
      def mount(_params, session, socket) do
        {:ok, PhoenixLLMChat.mount(socket, session)}
      end

  In your handle_event/3:
      def handle_event(event, params, socket) do
        PhoenixLLMChat.handle_event(event, params, socket)
      end

  In your handle_info/2:
      def handle_info(message, socket) do
        PhoenixLLMChat.handle_info(message, socket)
      end

  ## Configuration

      config :phoenix_llm_chat,
        default_provider: "claude",
        session_store: MyApp.FileSessionStore,
        hooks: %{
          :call_llm_stream => &MyApp.LLM.stream/4,
          :build_system_prompt => &MyApp.LLM.system_prompt/2,
          :persist_session => &MyApp.Storage.persist/2
        }
  """

  require Logger
  alias PhoenixLLMChat.{Core, Workspace}

  def mount(socket, session) do
    Core.mount(socket, session)
  end

  def handle_event(event, params, socket) do
    Core.handle_event(event, params, socket)
  rescue
    e ->
      Logger.error("Event error: #{event} - #{inspect(e)}")
      {:noreply, assign(socket, :error, "An error occurred")}
  end

  def handle_info(message, socket) do
    Core.handle_info(message, socket)
  rescue
    e ->
      Logger.error("Info error: #{inspect(message)} - #{inspect(e)}")
      {:noreply, socket}
  end

  def terminate(reason, socket) do
    Core.terminate(reason, socket)
  end

  # Workspace operations
  def create_session(socket, session_id, initial_data \\ %{}) do
    Workspace.create_session(socket, session_id, initial_data)
  end

  def open_session(socket, session_id) do
    Workspace.open_session(socket, session_id)
  end

  def switch_session(socket, session_id) do
    Workspace.switch_session(socket, session_id)
  end

  def delete_session(socket, session_id, session_store_impl) do
    Workspace.delete_session(socket, session_id, session_store_impl)
  end

  def rename_session(socket, session_id, new_name) do
    Workspace.rename_session(socket, session_id, new_name)
  end

  def hydrate_workspace(socket, session_store_impl) do
    Workspace.hydrate_workspace(socket, session_store_impl)
  end
end
