# PhoenixLLMChat

A generic, extensible Phoenix LiveView chat component with streaming LLM support and multi-tab session management.

## Features

- **Streaming LLM Support**: Works with Claude, Codex, LM Studio, or custom HTTP providers
- **Multi-Tab Sessions**: Built-in workspace with session switching, renaming, and deletion
- **Async Task Management**: Proper request ref correlation and task lifecycle cleanup
- **Extensible via Hooks**: Configure providers, build system prompts, persist sessions
- **Zero Foundry Dependencies**: Fully generic — reusable in any Phoenix app
- **File-Backed Storage**: Default file session store with custom backend support

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_llm_chat, path: "packages/phoenix_llm_chat"}
  ]
end
```

## Quick Start

### 1. Configure Providers

In `config/config.exs`:

```elixir
config :phoenix_llm_chat,
  default_provider: "claude",
  session_store: MyApp.FileSessionStore,
  hooks: %{
    :call_llm_stream => &MyApp.LLM.stream/4,
    :build_system_prompt => &MyApp.LLM.system_prompt/2,
    :persist_session => &MyApp.Storage.persist/2
  }
```

### 2. Mount in Your LiveView

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  def mount(_params, session, socket) do
    {:ok, PhoenixLLMChat.mount(socket, session)}
  end

  def handle_event(event, params, socket) do
    PhoenixLLMChat.handle_event(event, params, socket)
  end

  def handle_info(message, socket) do
    PhoenixLLMChat.handle_info(message, socket)
  end

  def terminate(reason, socket) do
    PhoenixLLMChat.terminate(reason, socket)
  end
end
```

### 3. Implement a Provider Hook

```elixir
defmodule MyApp.LLM do
  def stream(:claude, _socket, messages, options) do
    # Start your LLM task and send events back:
    # send(self(), {:llm_stream_delta, request_ref, token})
    # send(self(), {:llm_stream_done, request_ref, metadata})
    {:ok, request_ref}
  end

  def system_prompt(socket, options) do
    {:ok, "You are a helpful assistant..."}
  end
end
```

## Architecture

### Modules

- **`PhoenixLLMChat`** — Main public API
- **`StreamRuntime`** — Async task and streaming event handling
- **`Workspace`** — Multi-tab session management
- **`LLMContext`** — Provider abstraction and dispatch
- **`Core`** — Event handler and message lifecycle
- **`Utilities`** — Response filtering, formatting, error handling

### Hook System

Configure custom behavior via application config:

```elixir
config :phoenix_llm_chat,
  hooks: %{
    :call_llm_stream => &handler/4,        # Provider implementation
    :build_system_prompt => &handler/2,    # Custom system prompt
    :persist_session => &handler/2,        # Save session to DB
    :load_session => &handler/1,           # Load session from DB
    :get_provider => &handler/1,           # Select provider at runtime
    :get_provider_config => &handler/1     # Provider-specific config
  }
```

### Session Store Behaviour

Implement `PhoenixLLMChat.Behaviours.SessionStore` for custom backends:

```elixir
defmodule MyApp.DBSessionStore do
  @behaviour PhoenixLLMChat.Behaviours.SessionStore

  def load(session_id) do
    case MyApp.Repo.get(MyApp.ChatSession, session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session.data}
    end
  end

  def save(session_id, data) do
    MyApp.Repo.insert_or_update(%MyApp.ChatSession{id: session_id, data: data})
  end

  def list do
    {:ok, MyApp.Repo.all(MyApp.ChatSession) |> Enum.map(& &1.id)}
  end

  def delete(session_id) do
    MyApp.Repo.delete_all(MyApp.ChatSession, id: session_id)
  end
end
```

## Extending for Your Domain

The package provides hook points and a stable public interface. For domain-specific logic:

1. Create a `YourApp.ChatDomainLogic` module
2. Implement hooks that call into your logic
3. Use the socket assignments as your state store
4. Keep domain logic separate from streaming/UI patterns

Example from Foundry:

```elixir
defmodule FoundryWeb.ChatSessionDomainLogic do
  # Foundry-specific: proposal management, activity tracking, etc.
  def apply_proposal(socket, proposal_id), do: ...
  def create_activity_run(socket, metadata), do: ...
end
```

## Testing

The package is tested in isolation from domain logic. Test your provider hooks separately:

```elixir
test "stream calls llm provider" do
  assert {:ok, request_ref} = PhoenixLLMChat.LLMContext.call_llm(socket, "hello")
  assert is_reference(request_ref)
end
```

## License

MIT
