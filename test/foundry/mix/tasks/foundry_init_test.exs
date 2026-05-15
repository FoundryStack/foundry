defmodule Mix.Tasks.Foundry.InitTest do
  use ExUnit.Case

  test "foundry.init creates full scaffold structure" do
    dir = System.tmp_dir!() |> Path.join("foundry_init_test_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)

    try do
      Mix.Tasks.Foundry.Init.run([dir])

      # Check that manifest was created
      assert File.exists?(Path.join(dir, ".foundry/manifest.exs"))

      # Check that doc directories were created
      assert File.dir?(Path.join(dir, "docs/adrs"))
      assert File.dir?(Path.join(dir, "docs/runbooks"))
      assert File.dir?(Path.join(dir, "docs/regulations"))

      # Second run should not raise (idempotent)
      Mix.Tasks.Foundry.Init.run([dir])

      # Directories should still exist
      assert File.dir?(Path.join(dir, "docs/adrs"))
      assert File.dir?(Path.join(dir, "docs/runbooks"))
      assert File.dir?(Path.join(dir, "docs/regulations"))
    after
      File.rm_rf!(dir)
    end
  end

  test "foundry.init raises for non-existent directory" do
    path = "/nonexistent/foundry_init_test_#{:rand.uniform(999)}"

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Foundry.Init.run([path])
    end
  end

  test "foundry.init uses current directory when no args provided" do
    cwd = File.cwd!()

    try do
      dir = System.tmp_dir!() |> Path.join("foundry_init_test_cwd_#{:rand.uniform(99999)}")
      File.mkdir_p!(dir)
      File.cd!(dir)

      Mix.Tasks.Foundry.Init.run([])

      # Check that at least the manifest was created
      assert File.exists?(Path.join(dir, ".foundry/manifest.exs"))
      assert File.dir?(Path.join(dir, "docs/adrs"))

      File.rm_rf!(dir)
    after
      File.cd!(cwd)
    end
  end
end
