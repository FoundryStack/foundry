defmodule Mix.Tasks.Foundry.Project.StatusTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @ref_root Path.expand("../../../../../../reference_projects/igaming", __DIR__)

  setup_all do
    :code.add_path(String.to_charlist(Path.join(@ref_root, "_build/dev/lib/igaming_ref/ebin")))
    :ok
  end

  describe "build_output/2" do
    test "returns valid JSON string for igaming reference project" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      assert is_binary(json)
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
    end

    test "decoded JSON contains required top-level keys" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)

      for key <- ~w[generated_at project project_type domain_type lint stack] do
        assert Map.has_key?(decoded, key), "Missing key: #{key}"
      end
    end

    test "project field matches manifest project_name" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)
      assert decoded["project"] == "IgamingRef"
    end

    test "domain_type matches manifest" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)
      assert decoded["domain_type"] == "igaming"
    end

    test "pretty: true produces multi-line JSON" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root, true)
      assert String.contains?(json, "\n")
    end

    test "pretty: false produces single-line compact JSON" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root, false)
      refute String.contains?(json, "\n")
    end

    test "lint key contains errors and warnings counts" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)
      lint = decoded["lint"]
      assert is_map(lint)
      assert Map.has_key?(lint, "errors")
      assert Map.has_key?(lint, "warnings")
    end

    test "generated_at is a valid ISO8601 timestamp" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)
      assert {:ok, _, _} = DateTime.from_iso8601(decoded["generated_at"])
    end

    test "domains is a list of strings" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)
      assert is_list(decoded["domains"])
      Enum.each(decoded["domains"], &assert(is_binary(&1)))
    end

    test "sensitive_modules is a list" do
      json = Mix.Tasks.Foundry.Project.Status.build_output(@ref_root)
      decoded = Jason.decode!(json)
      assert is_list(decoded["sensitive_modules"])
    end
  end
end
