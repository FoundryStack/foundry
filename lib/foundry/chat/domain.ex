defmodule Foundry.Chat do
  @moduledoc """
  Ash domain for the chat session store.

  Sessions are persisted in Mnesia (disc_copies) so they survive server
  restarts without introducing a new database dependency. Mnesia is part of
  OTP and requires zero additional packages.

  This domain is intentionally separate from `Foundry.Context` — chat sessions
  are a UI concern, not an MCP tool surface.
  """

  use Ash.Domain

  resources do
    resource Foundry.Chat.Session
  end
end
