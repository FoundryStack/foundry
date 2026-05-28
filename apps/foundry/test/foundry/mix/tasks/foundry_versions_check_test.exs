defmodule Mix.Tasks.Foundry.Versions.CheckTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  # Use the Foundry umbrella root — it has a mix.lock
  @project_root Path.expand("../../../../../../", __DIR__)

  describe "build_output/1" do
    test "returns valid JSON string" do
      json = Mix.Tasks.Foundry.Versions.Check.build_output(@project_root)
      assert is_binary(json)
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
    end

    test "contains elixir_version and otp_version" do
      json = Mix.Tasks.Foundry.Versions.Check.build_output(@project_root)
      decoded = Jason.decode!(json)
      assert is_binary(decoded["elixir_version"])
      assert is_binary(decoded["otp_version"])
      assert decoded["elixir_version"] =~ ~r/^\d+\.\d+/
    end

    test "contains generated_at ISO8601 timestamp" do
      json = Mix.Tasks.Foundry.Versions.Check.build_output(@project_root)
      decoded = Jason.decode!(json)
      assert {:ok, _, _} = DateTime.from_iso8601(decoded["generated_at"])
    end

    test "all known deps are present as keys (values may be null)" do
      json = Mix.Tasks.Foundry.Versions.Check.build_output(@project_root)
      decoded = Jason.decode!(json)

      for dep <- Mix.Tasks.Foundry.Versions.Check.known_deps() do
        key = Atom.to_string(dep)
        assert Map.has_key?(decoded, key), "Missing dep key: #{key}"
      end
    end

    test "known deps in this project's mix.lock have non-null versions" do
      json = Mix.Tasks.Foundry.Versions.Check.build_output(@project_root)
      decoded = Jason.decode!(json)

      # ash and phoenix are definitely in the Foundry project's mix.lock
      assert is_binary(decoded["ash"]), "Expected ash version to be present"
      assert is_binary(decoded["phoenix"]), "Expected phoenix version to be present"
    end

    test "raises Mix.Error when mix.lock is absent" do
      dir = System.tmp_dir!() |> Path.join("foundry_ver_test_#{:rand.uniform(99999)}")
      File.mkdir_p!(dir)

      try do
        assert_raise Mix.Error, ~r/mix.lock not found/, fn ->
          Mix.Tasks.Foundry.Versions.Check.build_output(dir)
        end
      after
        File.rm_rf!(dir)
      end
    end
  end
end
