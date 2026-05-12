defmodule PhoenixLLMChat.Behaviours.SessionStore do
  @moduledoc """
  Behaviour for session persistence backends.

  Implementations can use files, databases, or any other storage mechanism.
  """

  @callback load(session_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback save(session_id :: String.t(), data :: map()) :: :ok | {:error, term()}
  @callback list() :: {:ok, [String.t()]} | {:error, term()}
  @callback delete(session_id :: String.t()) :: :ok | {:error, term()}
end
