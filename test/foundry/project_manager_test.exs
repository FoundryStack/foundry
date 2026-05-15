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
end
