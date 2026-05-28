defmodule Mix.Tasks.Foundry.Lint.AllTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @ref_root Path.expand("../../../../../../reference_projects/igaming", __DIR__)

  setup_all do
    :code.add_path(String.to_charlist(Path.join(@ref_root, "_build/dev/lib/igaming_ref/ebin")))
    :ok
  end

  describe "run_lint/2 with igaming reference project" do
    test "returns a LintReport struct" do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)
        assert %Foundry.Lint.LintReport{} = report
      end)
    end

    test "report has passed boolean field" do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)
        assert is_boolean(report.passed)
      end)
    end

    test "violations is a list" do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)
        assert is_list(report.violations)
      end)
    end

    test "error_count, warning_count, info_count are non-negative integers" do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)
        assert report.error_count >= 0
        assert report.warning_count >= 0
        assert report.info_count >= 0
      end)
    end

    test "violations are sorted: errors first, then warnings, then info" do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)

        severity_values = Enum.map(report.violations, fn v ->
          case v.severity do
            :error -> 0
            :warning -> 1
            :info -> 2
          end
        end)

        assert severity_values == Enum.sort(severity_values)
      end)
    end

    test "outputs JSON to stdout by default" do
      output = capture_io(fn ->
        Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)
      end)

      assert {:ok, decoded} = Jason.decode(output)
      assert Map.has_key?(decoded, "violations")
      assert Map.has_key?(decoded, "passed")
    end

    test "passed is true when error_count is 0" do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(@ref_root)
        assert report.passed == (report.error_count == 0)
      end)
    end
  end

  describe "run_lint/2 with empty project" do
    setup do
      dir = System.tmp_dir!() |> Path.join("foundry_lint_test_#{:rand.uniform(99999)}")
      File.mkdir_p!(Path.join(dir, "lib"))
      File.mkdir_p!(Path.join(dir, ".foundry"))
      File.write!(Path.join(dir, ".foundry/manifest.exs"), "[project_name: \"Empty\"]")
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns LintReport for an empty project", %{dir: dir} do
      capture_io(fn ->
        report = Mix.Tasks.Foundry.Lint.All.run_lint(dir)
        assert %Foundry.Lint.LintReport{} = report
        assert is_integer(report.error_count)
        assert is_boolean(report.passed)
        assert report.passed == (report.error_count == 0)
      end)
    end
  end
end
