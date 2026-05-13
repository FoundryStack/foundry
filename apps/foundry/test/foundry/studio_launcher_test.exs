defmodule Foundry.StudioLauncherTest do
  use ExUnit.Case, async: false

  alias Foundry.Studio

  setup do
    tmp_root =
      Path.join(
        System.tmp_dir!(),
        "foundry-studio-launcher-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf(tmp_root)
    File.mkdir_p!(tmp_root)

    home_root = Path.join(tmp_root, "home")
    File.mkdir_p!(home_root)

    previous_home = System.get_env("HOME")
    previous_foundry_home = System.get_env("FOUNDRY_HOME")
    System.put_env("HOME", home_root)
    System.put_env("FOUNDRY_HOME", home_root)

    on_exit(fn ->
      if previous_home do
        System.put_env("HOME", previous_home)
      else
        System.delete_env("HOME")
      end

      if previous_foundry_home do
        System.put_env("FOUNDRY_HOME", previous_foundry_home)
      else
        System.delete_env("FOUNDRY_HOME")
      end

      File.rm_rf(tmp_root)
    end)

    {:ok, tmp_root: tmp_root, home_root: home_root}
  end

  test "find_open_port skips an occupied port" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)

    on_exit(fn -> :gen_tcp.close(listener) end)

    assert {:ok, next_port} = Studio.find_open_port(port)
    assert next_port > port
  end

  test "writes and reads the port file", %{home_root: home_root} do
    assert :ok = Studio.write_port_file(4311)
    assert Studio.port_file_path() == Path.join(home_root, ".foundry.port")
    assert {:ok, 4311} = Studio.read_port_file()
  end

  test "ignores invalid port file contents" do
    File.write!(Studio.port_file_path(), "not-a-port\n")
    assert {:error, :invalid_port} = Studio.read_port_file()
  end
end
