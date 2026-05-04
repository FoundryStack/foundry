defmodule Foundry.Context.ScenarioExtractorTest do
  use ExUnit.Case, async: true

  alias Foundry.Context.NodeEntry
  alias Foundry.Context.ScenarioExtractor

  describe "extract/2" do
    test "returns empty list when test directory does not exist" do
      project_root = "/nonexistent/path"
      nodes_map = []

      result = ScenarioExtractor.extract(project_root, nodes_map)
      assert result == []
    end

    test "extracts scenarios from test file with @moduletag metadata" do
      tmpdir = System.tmp_dir!() <> "/foundry_test_#{System.unique_integer()}"
      File.mkdir_p(tmpdir)
      test_file = Path.join([tmpdir, "test", "test_scenario.exs"])
      File.mkdir_p(Path.dirname(test_file))

      content = """
      defmodule TestModule do
        describe "Withdrawal scenario" do
          @moduletag category: :compliance
          @moduletag nodes: ["Finance.Wallet", "Finance.Transfer"]
          @moduletag graph_path: ["Finance.Wallet", "Finance.Transfer"]
          @moduletag compliance_links: ["RG-UK-001"]
          @moduletag steps: %{
            given: ["A wallet exists"],
            when: ["A withdrawal is requested"],
            then: ["The wallet is debited"]
          }

          test "processes withdrawal" do
            :ok
          end
        end
      end
      """

      File.write(test_file, content)

      scenarios = ScenarioExtractor.extract(tmpdir, [])

      assert Enum.count(scenarios) > 0
      scenario = Enum.at(scenarios, 0)
      assert scenario.category == :compliance
      assert "Finance.Wallet" in scenario.nodes
      assert "RG-UK-001" in scenario.compliance_links

      File.rm_rf(tmpdir)
    end

    test "handles describe blocks with variant syntax" do
      tmpdir = System.tmp_dir!() <> "/foundry_test_#{System.unique_integer()}"
      File.mkdir_p(tmpdir)
      test_file = Path.join([tmpdir, "test", "test_variant.exs"])
      File.mkdir_p(Path.dirname(test_file))

      content = """
      defmodule TestModule do
        describe "Invariant test" do
          @moduletag category: :invariant
          @moduletag nodes: ["Rule.Balance"]

          test "balance invariant" do
            :ok
          end
        end
      end
      """

      File.write(test_file, content)

      scenarios = ScenarioExtractor.extract(tmpdir, [])

      assert Enum.count(scenarios) > 0
      scenario = Enum.at(scenarios, 0)
      assert scenario.category == :invariant

      File.rm_rf(tmpdir)
    end

    test "resolves shorthand node names against graph node ids from a node list" do
      tmpdir = System.tmp_dir!() <> "/foundry_test_#{System.unique_integer()}"
      File.mkdir_p(tmpdir)
      test_file = Path.join([tmpdir, "test", "bonus_scenario.exs"])
      File.mkdir_p(Path.dirname(test_file))

      content = """
      defmodule IgamingRef.Finance.BonusScenarioTest do
        describe "Property: Bonus value never exceeds deposit" do
          @moduletag category: :property
          @moduletag nodes: ["Finance.Bonus"]
          @moduletag graph_path: ["Finance.Bonus"]

          test "bonus never exceeds limits" do
            :ok
          end
        end
      end
      """

      File.write(test_file, content)

      nodes = [
        %NodeEntry{
          id: "IgamingRef.Finance.Bonus",
          module: "IgamingRef.Finance.Bonus",
          type: "resource",
          domain: "Finance",
          description: "Bonus resource"
        },
        %NodeEntry{
          id: "IgamingRef.Finance.WageringRequirement",
          module: "IgamingRef.Finance.WageringRequirement",
          type: "resource",
          domain: "Finance",
          description: "Wagering requirement resource"
        }
      ]

      scenarios = ScenarioExtractor.extract(tmpdir, nodes)

      assert Enum.count(scenarios) > 0
      scenario = Enum.at(scenarios, 0)
      assert scenario.nodes == ["IgamingRef.Finance.Bonus"]
      assert scenario.graph_path == ["IgamingRef.Finance.Bonus"]

      File.rm_rf(tmpdir)
    end

    test "ignores describe blocks without category tag" do
      tmpdir = System.tmp_dir!() <> "/foundry_test_#{System.unique_integer()}"
      File.mkdir_p(tmpdir)
      test_file = Path.join([tmpdir, "test", "test_no_tags.exs"])
      File.mkdir_p(Path.dirname(test_file))

      content = """
      defmodule TestModule do
        describe "Regular test without scenario metadata" do
          test "regular test" do
            :ok
          end
        end
      end
      """

      File.write(test_file, content)

      scenarios = ScenarioExtractor.extract(tmpdir, [])

      assert scenarios == []

      File.rm_rf(tmpdir)
    end

    test "generates scenario ID from module and describe name" do
      tmpdir = System.tmp_dir!() <> "/foundry_test_#{System.unique_integer()}"
      File.mkdir_p(tmpdir)
      test_file = Path.join([tmpdir, "test", "test_id.exs"])
      File.mkdir_p(Path.dirname(test_file))

      content = """
      defmodule MyAppTest do
        describe "Test scenario name" do
          @moduletag category: :invariant

          test "test" do
            :ok
          end
        end
      end
      """

      File.write(test_file, content)

      scenarios = ScenarioExtractor.extract(tmpdir, [])

      assert Enum.count(scenarios) > 0
      scenario = Enum.at(scenarios, 0)
      assert String.contains?(scenario.id, "test_scenario_name")

      File.rm_rf(tmpdir)
    end
  end
end
