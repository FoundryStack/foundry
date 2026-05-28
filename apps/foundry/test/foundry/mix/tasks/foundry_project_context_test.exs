defmodule Mix.Tasks.Foundry.Project.ContextTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @ref_root Path.expand("../../../../../../reference_projects/igaming", __DIR__)

  setup_all do
    :code.add_path(String.to_charlist(Path.join(@ref_root, "_build/dev/lib/igaming_ref/ebin")))
    :ok
  end

  describe "run_single/2" do
    test "returns {:ok, json} for a known module" do
      output = capture_io(fn ->
        result = Mix.Tasks.Foundry.Project.Context.run_single(
          "IgamingRef.Finance.Wallet",
          @ref_root
        )
        assert {:ok, json} = result
        assert is_binary(json)
        assert {:ok, _} = Jason.decode(json)
      end)

      assert is_binary(output)
    end

    test "JSON for known module has id and type fields" do
      capture_io(fn ->
        {:ok, json} = Mix.Tasks.Foundry.Project.Context.run_single(
          "IgamingRef.Finance.Wallet",
          @ref_root
        )
        decoded = Jason.decode!(json)
        assert Map.has_key?(decoded, "id")
        assert Map.has_key?(decoded, "type")
      end)
    end

    test "returns {:error, :module_not_found} for unknown module" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Project.Context.run_single(
          "IgamingRef.DoesNot.Exist",
          @ref_root
        )
        assert {:error, :module_not_found} = result
      end)
    end

    test "unknown module outputs JSON error object to stdout" do
      output = capture_io(fn ->
        Mix.Tasks.Foundry.Project.Context.run_single(
          "IgamingRef.DoesNot.Exist",
          @ref_root
        )
      end)

      decoded = Jason.decode!(output)
      assert decoded["error"] == "module_not_found"
      assert decoded["module"] == "IgamingRef.DoesNot.Exist"
    end
  end

  describe "run_check/1" do
    setup do
      # Use a fresh temp dir for each check test to avoid polluting @ref_root
      dir = System.tmp_dir!() |> Path.join("foundry_ctx_check_#{:rand.uniform(99999)}")
      File.mkdir_p!(Path.join(dir, ".foundry"))
      File.mkdir_p!(Path.join(dir, "lib"))
      File.mkdir_p!(Path.join(dir, "test"))
      File.write!(Path.join(dir, "lib/placeholder.ex"), "# placeholder")
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns {:error, :missing} when lock file absent", %{dir: dir} do
      output = capture_io(:stderr, fn ->
        assert {:error, :missing} = Mix.Tasks.Foundry.Project.Context.run_check(dir)
      end)

      assert String.contains?(output, "absent")
    end

    test "returns :ok when lock file is current", %{dir: dir} do
      Foundry.Context.LockFile.write(dir)

      output = capture_io(fn ->
        assert :ok = Mix.Tasks.Foundry.Project.Context.run_check(dir)
      end)

      assert String.contains?(output, "current")
    end

    test "returns {:error, :stale} when lock file is stale", %{dir: dir} do
      Foundry.Context.LockFile.write(dir)
      # Modify a file to make hash stale
      File.write!(Path.join(dir, "lib/placeholder.ex"), "# modified")

      output = capture_io(:stderr, fn ->
        assert {:error, :stale} = Mix.Tasks.Foundry.Project.Context.run_check(dir)
      end)

      assert String.contains?(output, "stale")
    end
  end
end
