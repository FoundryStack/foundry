defmodule Foundry.RuntimeConfig do
  @moduledoc false

  def standalone?, do: System.get_env("FOUNDRY_STANDALONE", "1") == "1"

  def preview_host do
    phx_host = System.get_env("PHX_HOST", "localhost")
    "preview." <> phx_host
  end

  def cloud_preview_port, do: 4002
end
