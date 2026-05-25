defmodule Foundry.ProjectManagerTest do
  use ExUnit.Case

  test "classify_folder/1 detects empty folder" do
    dir = System.tmp_dir!() |> Path.join("pm_test_empty_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      assert Foundry.ProjectManager.classify_folder(dir) == :empty_folder
    after
      File.rm_rf!(dir)
    end
  end

  test "classify_folder/1 detects partial project (mix.exs without .foundry)" do
    dir = System.tmp_dir!() |> Path.join("pm_test_partial_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      File.write!(Path.join(dir, "mix.exs"), "# Mix project")
      assert Foundry.ProjectManager.classify_folder(dir) == :partial_project
    after
      File.rm_rf!(dir)
    end
  end

  test "classify_folder/1 detects existing project (mix.exs + .foundry)" do
    dir = System.tmp_dir!() |> Path.join("pm_test_existing_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      File.write!(Path.join(dir, "mix.exs"), "# Mix project")
      File.mkdir_p!(Path.join(dir, ".foundry"))
      assert Foundry.ProjectManager.classify_folder(dir) == :existing_project
    after
      File.rm_rf!(dir)
    end
  end

  test "classify_folder/1 returns error for non-existent directory" do
    path = "/nonexistent/path_#{:rand.uniform(999)}"
    assert Foundry.ProjectManager.classify_folder(path) == {:error, :not_a_directory}
  end

  test "classify_folder/1 handles paths with spaces and expands paths" do
    dir = System.tmp_dir!() |> Path.join("pm_test_spaces #{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      result = Foundry.ProjectManager.classify_folder("  #{dir}  ")
      assert result == :empty_folder
    after
      File.rm_rf!(dir)
    end
  end

  describe "clone_project/2 idempotency" do
    setup do
      src = System.tmp_dir!() |> Path.join("pm_src_#{:rand.uniform(99999)}")
      dest_parent = System.tmp_dir!() |> Path.join("pm_dest_#{:rand.uniform(99999)}")
      File.mkdir_p!(src)
      File.mkdir_p!(dest_parent)

      System.cmd("git", ["init", src])
      System.cmd("git", ["-C", src, "config", "user.email", "test@test.com"])
      System.cmd("git", ["-C", src, "config", "user.name", "Test"])
      File.write!(Path.join(src, "mix.exs"), "defmodule T.MixProject do\n  use Mix.Project\n  def project, do: [app: :t, version: \"0.1.0\"]\nend\n")
      System.cmd("git", ["-C", src, "add", "."])
      System.cmd("git", ["-C", src, "commit", "-m", "init"])

      on_exit(fn ->
        File.rm_rf!(src)
        File.rm_rf!(dest_parent)
      end)

      %{repo_url: src, dest_parent: dest_parent}
    end

    defp wait_for_terminal_status(timeout_ms \\ 10_000) do
      deadline = System.monotonic_time(:millisecond) + timeout_ms

      Stream.repeatedly(fn -> Process.sleep(100) end)
      |> Enum.reduce_while(nil, fn _, _ ->
        status = Foundry.ProjectManager.get_status()

        cond do
          status.state in [:ready, :failed] -> {:halt, status}
          System.monotonic_time(:millisecond) >= deadline -> {:halt, status}
          true -> {:cont, nil}
        end
      end)
    end

    test "succeeds when target does not exist", %{repo_url: repo_url, dest_parent: dest_parent} do
      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      status = wait_for_terminal_status()
      assert status.state == :ready, "Expected :ready, got: #{status.state} — #{inspect(status.last_error)}"
    end

    test "reuses existing valid clone without error", %{repo_url: repo_url, dest_parent: dest_parent} do
      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      first_status = wait_for_terminal_status()
      assert first_status.state == :ready

      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      second_status = wait_for_terminal_status()
      assert second_status.state == :ready, "Second clone failed: #{inspect(second_status.last_error)}"
    end

    test "removes incomplete clone and re-clones", %{repo_url: repo_url, dest_parent: dest_parent} do
      repo_name = Path.basename(repo_url)
      broken_path = Path.join(dest_parent, repo_name)
      File.mkdir_p!(broken_path)
      File.write!(Path.join(broken_path, "junk"), "partial")

      Foundry.ProjectManager.clone_project(repo_url, dest_parent)
      status = wait_for_terminal_status()

      assert status.state == :ready, "Expected :ready after re-clone, got: #{status.state} — #{inspect(status.last_error)}"
      assert File.dir?(Path.join(broken_path, ".git"))
    end
  end
end
