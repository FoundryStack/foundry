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

  test "mix_task_invoked? detects phx.server from plain init arguments" do
    assert Studio.mix_task_invoked?("phx.server",
             argv: [],
             plain_args: [~c"--no-halt", ~c"+iex", ~c"-S", ~c"mix", ~c"phx.server"]
           )
  end

  test "mix_task_invoked? detects phx.server from an absolute mix path" do
    assert Studio.mix_task_invoked?("phx.server",
             argv: [],
             plain_args: [~c"--no-halt", ~c"/opt/homebrew/bin/mix", ~c"phx.server"]
           )
  end

  test "mix_task_invoked? detects studio from argv" do
    assert Studio.mix_task_invoked?("foundry.studio",
             argv: ["foundry.studio", "--port", "4001"],
             plain_args: []
           )
  end

  test "mix_task_invoked? ignores unrelated commands" do
    refute Studio.mix_task_invoked?("phx.server",
             argv: ["test"],
             plain_args: [~c"--no-halt", ~c"-S", ~c"mix", ~c"test"]
           )
  end
end
