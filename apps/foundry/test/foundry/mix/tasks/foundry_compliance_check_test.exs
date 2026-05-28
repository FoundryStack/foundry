defmodule Mix.Tasks.Foundry.Compliance.CheckTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @ref_root Path.expand("../../../../../../reference_projects/igaming", __DIR__)

  describe "run_check/2 with igaming reference project" do
    test "returns a CheckResult struct" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
        assert %Foundry.Compliance.CheckResult{} = result
      end)
    end

    test "requirements list is non-empty (RG-* entries exist in regulations)" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
        assert is_list(result.requirements)
        assert length(result.requirements) > 0
      end)
    end

    test "each requirement has id, summary, and status" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)

        Enum.each(result.requirements, fn req ->
          assert is_binary(req.id)
          assert String.starts_with?(req.id, "RG-")
          assert is_binary(req.summary)
          assert req.status in [:implemented, :partial, :unimplemented, :planned]
        end)
      end)
    end

    test "requirements are sorted by id" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
        ids = Enum.map(result.requirements, & &1.id)
        assert ids == Enum.sort(ids)
      end)
    end

    test "summary counts match requirements list" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
        total = length(result.requirements)
        assert result.summary.total == total

        counted =
          result.summary.implemented +
          result.summary.partial +
          result.summary.unimplemented +
          result.summary.planned

        assert counted == total
      end)
    end

    test "generated_at is a valid ISO8601 timestamp" do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
        assert {:ok, _, _} = DateTime.from_iso8601(result.generated_at)
      end)
    end

    test "outputs JSON to stdout" do
      output = capture_io(fn ->
        Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
      end)

      assert {:ok, decoded} = Jason.decode(output)
      assert Map.has_key?(decoded, "requirements")
      assert Map.has_key?(decoded, "summary")
    end

    test "filter by prefix reduces results" do
      full_output = capture_io(fn ->
        Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root)
      end)

      mga_output = capture_io(fn ->
        Mix.Tasks.Foundry.Compliance.Check.run_check(@ref_root, ["--filter=RG-MGA"])
      end)

      full = Jason.decode!(full_output)
      mga = Jason.decode!(mga_output)

      # Filtered list should be a subset
      assert length(mga["requirements"]) <= length(full["requirements"])
      # All filtered results start with RG-MGA
      Enum.each(mga["requirements"], fn r ->
        assert String.starts_with?(r["id"], "RG-MGA")
      end)
    end
  end

  describe "run_check/2 with empty project (no regulations)" do
    setup do
      dir = System.tmp_dir!() |> Path.join("foundry_comp_test_#{:rand.uniform(99999)}")
      File.mkdir_p!(Path.join(dir, "docs/regulations"))
      File.mkdir_p!(Path.join(dir, ".foundry"))
      File.write!(Path.join(dir, ".foundry/manifest.exs"), "[project_name: \"Test\"]")
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns CheckResult with empty requirements", %{dir: dir} do
      capture_io(fn ->
        result = Mix.Tasks.Foundry.Compliance.Check.run_check(dir)
        assert %Foundry.Compliance.CheckResult{} = result
        assert result.requirements == []
        assert result.summary.total == 0
      end)
    end
  end
end
