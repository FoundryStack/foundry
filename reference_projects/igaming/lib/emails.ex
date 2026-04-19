defmodule IgamingRef.Accounts.Emails.PasswordResetEmail do
  @moduledoc """
  Stub for Password Reset Emails to satisfy AshAuthentication.Sender behaviour.
  """
  use AshAuthentication.Sender

  @impl true
  def send(_user, _token, _opts) do
    # In a real system, this would trigger a Swoosh email or Oban job.
    :ok
  end
end

defmodule IgamingRef.Accounts.Emails.MagicLinkEmail do
  @moduledoc """
  Stub for Magic Link Emails to satisfy AshAuthentication.Sender behaviour.
  """
  use AshAuthentication.Sender

  @impl true
  def send(_user, _token, _opts) do
    # In a real system, this would trigger a Swoosh email or Oban job.
    :ok
  end
end
