defmodule Foundry.StudioCliTest do
  use ExUnit.Case, async: true

  alias Foundry.Studio

  test "parse_studio_argv parses explicit launch arguments" do
    assert {:ok, opts} =
             Studio.parse_studio_argv([
               "studio",
               "--project",
               "/tmp/foundry",
               "--port",
               "4100",
               "--no-browser"
             ])

    assert opts[:project_root] == "/tmp/foundry"
    assert opts[:port] == 4100
    refute opts[:open_browser?]
  end

  test "parse_studio_argv supports auto port by default" do
    assert {:ok, opts} = Studio.parse_studio_argv(["studio"])

    assert opts[:port] == :auto
    assert opts[:project_root] == File.cwd!()
    assert opts[:open_browser?]
  end

  test "parse_studio_argv ignores unrelated argv" do
    assert :no_command = Studio.parse_studio_argv(["version"])
  end

  test "parse_studio_argv rejects invalid ports" do
    assert {:error, message} = Studio.parse_studio_argv(["studio", "--port", "nope"])
    assert message =~ "--port"
  end
end
