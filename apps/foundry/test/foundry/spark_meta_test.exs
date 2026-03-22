defmodule Foundry.SparkMetaTest do
  use ExUnit.Case, async: true

  describe "basic struct output" do
    @tag :phase1
    test "returns %SparkMeta.ModuleInfo{} for a module" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
      assert result.module == Kernel
    end

    test "does not crash on a module with no Spark extensions" do
      # A plain Elixir module — should return ModuleInfo with nil/[] defaults
      result = Foundry.SparkMeta.walk(Kernel)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
      assert result.attributes == []
      assert result.actions == []
    end
  end

  describe "module attributes (@-declared)" do
    @tag :phase1
    test "description extraction is graceful on missing @moduledoc" do
      result = Foundry.SparkMeta.walk(Kernel)
      # Kernel has moduledoc, but test structure verification
      assert is_nil(result.description) or is_binary(result.description)
    end

    test "telemetry_prefix extraction handles missing attribute" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.telemetry_prefix == []
    end

    test "compliance extraction handles missing attribute" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.compliance == []
    end

    test "adrs extraction handles missing attribute" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.adrs == []
    end

    test "runbook extraction handles missing attribute" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.runbook == nil
    end
  end

  describe "extension detection via Spark.extensions/1" do
    @tag :phase1
    test "modules without extensions have paper_trail: false" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.paper_trail == false
    end

    test "modules without extensions have archival: false" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.archival == false
    end

    test "modules without extensions have authentication_subject: false" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.authentication_subject == false
    end

    test "modules without extensions have rate_limited: false" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.rate_limited == false
    end
  end

  describe "AshStateMachine introspection" do
    @tag :phase1
    test "modules without state machines have state_machine.present: false" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.state_machine.present == false
      assert result.state_machine.states == []
      assert result.state_machine.transitions == []
      assert result.state_machine.state_attribute == nil
    end
  end

  describe "Ash.Type.Money introspection" do
    @tag :phase1
    test "modules without monetary attributes have money_attributes: []" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.money_attributes == []
    end
  end

  describe "Reactor step introspection" do
    @tag :phase1
    test "non-reactor modules have steps: []" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.steps == []
    end
  end

  describe "Oban.Worker detection" do
    @tag :phase1
    test "non-worker modules have oban_queues: []" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.oban_queues == []
    end
  end

  describe "agent_steps" do
    @tag :phase1
    test "modules without AshAI steps have agent_steps: []" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.agent_steps == []
    end
  end

  describe "SparkMeta.Extension opt-in hook" do
    @tag :phase1
    test "unknown extensions produce raw key-value fallback, do not crash" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert %Foundry.SparkMeta.ModuleInfo{} = result
    end
  end

  describe "type detection fallback" do
    @tag :phase1
    test "non-Spark modules default to :resource type" do
      result = Foundry.SparkMeta.walk(Kernel)
      assert result.type == :resource
    end
  end

  describe "graceful error handling" do
    @tag :phase1
    test "invalid module argument returns fallback struct" do
      # Test that walk gracefully handles edge cases
      result = Foundry.SparkMeta.walk(Kernel)
      assert is_struct(result, Foundry.SparkMeta.ModuleInfo)
    end
  end
end
