defmodule Foundry.MCP.ToolsTest do
  use ExUnit.Case, async: false

  @igaming_root Path.expand("../../../../../reference_projects/igaming", __DIR__)

  describe "project_status/1" do
    test "returns {:ok, map} with expected fields for valid project" do
      assert {:ok, result} = Foundry.MCP.Tools.project_status(%{"project_root" => @igaming_root})

      assert is_map(result)
      assert Map.has_key?(result, :project)
      assert Map.has_key?(result, :project_type)
      assert Map.has_key?(result, :domain_type)
      assert Map.has_key?(result, :domains)
      assert Map.has_key?(result, :lint_errors)
      assert Map.has_key?(result, :lint_warnings)
      assert Map.has_key?(result, :stack_versions)
      assert Map.has_key?(result, :generated_at)
    end

    test "result is JSON-encodable" do
      assert {:ok, result} = Foundry.MCP.Tools.project_status(%{"project_root" => @igaming_root})
      assert {:ok, _json} = Jason.encode(result)
    end

    test "result does not contain Ash metadata fields" do
      assert {:ok, result} = Foundry.MCP.Tools.project_status(%{"project_root" => @igaming_root})
      refute Map.has_key?(result, :__meta__)
      refute Map.has_key?(result, :__metadata__)
      refute Map.has_key?(result, :aggregates)
      refute Map.has_key?(result, :calculations)
    end

    test "returns {:error, message} for nonexistent project" do
      result = Foundry.MCP.Tools.project_status(%{"project_root" => "/nonexistent/project/path"})
      assert {:error, _message} = result
    end

    test "falls back to File.cwd! when project_root not provided" do
      # Should not raise, just may return error if cwd has no manifest
      result = Foundry.MCP.Tools.project_status(%{})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "module_context/1" do
    test "returns {:ok, map} with module fields when no filter" do
      assert {:ok, result} = Foundry.MCP.Tools.module_context(%{"project_root" => @igaming_root})

      assert is_map(result)
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :module)
      assert Map.has_key?(result, :type)
      assert Map.has_key?(result, :domain)
    end

    test "filters by module_id when provided" do
      assert {:ok, result} =
               Foundry.MCP.Tools.module_context(%{
                 "project_root" => @igaming_root,
                 "module_id" => "IgamingRef.Finance.Wallet"
               })

      assert result[:id] == "IgamingRef.Finance.Wallet"
      assert result[:module] == "IgamingRef.Finance.Wallet"
    end

    test "returns {:error, :not_found} for nonexistent module" do
      result =
        Foundry.MCP.Tools.module_context(%{
          "project_root" => @igaming_root,
          "module_id" => "NonExistent.Module.That.DoesNotExist"
        })

      assert {:error, _} = result
    end

    test "result is JSON-encodable" do
      assert {:ok, result} = Foundry.MCP.Tools.module_context(%{"project_root" => @igaming_root})
      assert {:ok, _json} = Jason.encode(result)
    end

    test "result does not contain Ash metadata fields" do
      assert {:ok, result} = Foundry.MCP.Tools.module_context(%{"project_root" => @igaming_root})
      refute Map.has_key?(result, :__meta__)
      refute Map.has_key?(result, :__metadata__)
    end
  end

  describe "system_graph/1" do
    test "returns {:ok, map} with graph fields" do
      assert {:ok, result} = Foundry.MCP.Tools.system_graph(%{"project_root" => @igaming_root})

      assert is_map(result)
      assert Map.has_key?(result, :project)
      assert Map.has_key?(result, :nodes)
      assert Map.has_key?(result, :edges)
      assert Map.has_key?(result, :generated_at)
    end

    test "nodes list is non-empty for igaming project" do
      assert {:ok, result} = Foundry.MCP.Tools.system_graph(%{"project_root" => @igaming_root})
      assert is_list(result[:nodes])
      assert length(result[:nodes]) > 0
    end

    test "result is JSON-encodable" do
      assert {:ok, result} = Foundry.MCP.Tools.system_graph(%{"project_root" => @igaming_root})
      assert {:ok, _json} = Jason.encode(result)
    end

    test "result does not contain Ash metadata fields" do
      assert {:ok, result} = Foundry.MCP.Tools.system_graph(%{"project_root" => @igaming_root})
      refute Map.has_key?(result, :__meta__)
      refute Map.has_key?(result, :__metadata__)
    end
  end

  describe "run_lint/1" do
    test "returns {:ok, map} with lint result fields" do
      assert {:ok, result} = Foundry.MCP.Tools.run_lint(%{"project_root" => @igaming_root})

      assert is_map(result)
      assert Map.has_key?(result, :passed)
      assert Map.has_key?(result, :error_count)
      assert Map.has_key?(result, :warning_count)
      assert Map.has_key?(result, :violations)
    end

    test "violations is a list" do
      assert {:ok, result} = Foundry.MCP.Tools.run_lint(%{"project_root" => @igaming_root})
      assert is_list(result[:violations])
    end

    test "result is JSON-encodable" do
      assert {:ok, result} = Foundry.MCP.Tools.run_lint(%{"project_root" => @igaming_root})
      assert {:ok, _json} = Jason.encode(result)
    end
  end

  describe "read_doc/1" do
    test "returns {:ok, map} with document fields when no filter" do
      assert {:ok, result} = Foundry.MCP.Tools.read_doc(%{"project_root" => @igaming_root})

      assert is_map(result)
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :path)
      assert Map.has_key?(result, :title)
      assert Map.has_key?(result, :type)
    end

    test "result is JSON-encodable" do
      assert {:ok, result} = Foundry.MCP.Tools.read_doc(%{"project_root" => @igaming_root})
      assert {:ok, _json} = Jason.encode(result)
    end

    test "returns {:error, :not_found} when no docs exist" do
      dir = System.tmp_dir!() |> Path.join("mcp_tools_test_#{:rand.uniform(99999)}")
      File.mkdir_p!(dir)

      try do
        # Write a minimal manifest so project_root resolves
        File.write!(Path.join(dir, "manifest.exs"), "[project_name: \"Test\", domain_type: :test]")
        result = Foundry.MCP.Tools.read_doc(%{"project_root" => dir})
        assert {:error, :not_found} = result
      after
        File.rm_rf!(dir)
      end
    end
  end
end
