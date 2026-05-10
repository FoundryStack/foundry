defmodule Foundry.Chat.SessionStore do
  @moduledoc """
  Behaviour for Studio copilot session persistence.

  Session stores handle create, read, update, delete, and listing of chat sessions.
  Each session is scoped to a workspace_id and project_fingerprint combination.
  """

  @type session_id :: String.t()
  @type workspace_id :: String.t()
  @type project_fingerprint :: String.t()
  @type session :: map()

  @doc "List all sessions for a workspace and project."
  @callback list(workspace_id :: workspace_id, project_fingerprint :: project_fingerprint) ::
              {:ok, [session()]} | {:error, term()}

  @doc "Load a single session by ID. Returns nil if not found."
  @callback load(session_id :: session_id) :: {:ok, session() | nil} | {:error, term()}

  @doc "Create a new session. Requires :id, :workspace_id, :project_fingerprint in attrs."
  @callback create(attrs :: map()) :: {:ok, session()} | {:error, term()}

  @doc "Update a session by ID. Merges attrs and bumps :updated_at."
  @callback update(session_id :: session_id, attrs :: map()) :: {:ok, session()} | {:error, term()}

  @doc "Rename a session by ID."
  @callback rename(session_id :: session_id, title :: String.t()) ::
              {:ok, session()} | {:error, term()}

  @doc "Delete a session by ID. Returns :ok even if not found."
  @callback delete(session_id :: session_id) :: :ok | {:error, term()}
end
