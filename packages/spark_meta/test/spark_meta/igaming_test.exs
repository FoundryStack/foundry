defmodule SparkMeta.IgamingTest do
  use ExUnit.Case
  @moduletag :integration

  @igaming_root "/Users/maxsvargal/Documents/Projects/foundry/reference_projects/igaming/_build/dev/lib"

  setup_all do
    :code.add_path(String.to_charlist(Path.join([@igaming_root, "igaming_ref", "ebin"])))

    for dep <- ["ash_state_machine", "ash_paper_trail", "ash_archival", "ash_postgres"] do
      path = Path.join([@igaming_root, dep, "ebin"])
      if File.dir?(path), do: :code.add_path(String.to_charlist(path))
    end

    {:module, _} = Code.ensure_loaded(IgamingRef.Finance.Wallet)
    :ok
  end

  test "walks IgamingRef.Finance.Wallet successfully" do
    {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)

    assert state.module == IgamingRef.Finance.Wallet
    assert is_list(state.extensions)
  end

  test "extracts extensions from igaming wallet" do
    extensions = SparkMeta.Walker.extensions(IgamingRef.Finance.Wallet)

    # Expect at least AshStateMachine, AshPaperTrail.Resource, AshArchival.Resource
    assert AshStateMachine in extensions or AshStateMachine.Dsl in extensions
    assert Enum.any?(extensions, &(to_string(&1) =~ "AshPaperTrail"))
    assert Enum.any?(extensions, &(to_string(&1) =~ "AshArchival"))
  end

  test "gets data_layer from wallet" do
    data_layer = SparkMeta.Walker.get_persisted(IgamingRef.Finance.Wallet, :data_layer, nil)

    assert data_layer == AshPostgres.DataLayer or data_layer == nil
  end

  test "extracts state machine transitions" do
    transitions =
      SparkMeta.Walker.entities(IgamingRef.Finance.Wallet, [:state_machine, :transitions])

    # Wallet should have transitions like freeze, unfreeze, close
    assert is_list(transitions)
    assert length(transitions) == 3

    # Verify transition structure
    assert Enum.all?(transitions, &(Map.get(&1, :action) in [:freeze, :unfreeze, :close]))
  end

  test "walks IgamingRef.Players.Player successfully" do
    {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Players.Player)

    assert state.module == IgamingRef.Players.Player
    assert is_list(state.extensions)
  end

  test "player has state machine transitions" do
    transitions =
      SparkMeta.Walker.entities(IgamingRef.Players.Player, [:state_machine, :transitions])

    # Player should have multiple transitions
    assert is_list(transitions)
    assert length(transitions) >= 3
  end

  describe "rich fields extraction via handler" do
    setup do
      :ets.delete_all_objects(:spark_meta_registry)
      SparkMeta.Registry.register(Ash.Resource.Dsl, SparkMeta.Handlers.AshResource)
      :ok
    end

    test "wallet moduledoc is a non-empty string" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      assert is_binary(state.moduledoc)
      assert String.length(state.moduledoc) > 10
    end

    test "wallet attributes include :player_id, :currency, :balance, :status" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      names = Enum.map(ash_data.attributes, & &1.name)
      assert :player_id in names
      assert :currency in names
      assert :balance in names
      assert :status in names
    end

    test "wallet :balance attribute has correct description and allow_nil? false" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      balance = Enum.find(ash_data.attributes, &(&1.name == :balance))
      assert balance != nil
      assert String.contains?(balance.description, "RG-MGA-001")
      assert balance.allow_nil? == false
    end

    test "wallet relationships include :player (belongs_to) and :ledger_entries (has_many)" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      names = Enum.map(ash_data.relationships, & &1.name)
      assert :player in names
      assert :ledger_entries in names
      player_rel = Enum.find(ash_data.relationships, &(&1.name == :player))
      assert player_rel.type == :belongs_to
      assert player_rel.destination == IgamingRef.Players.Player
    end

    test "wallet actions include :create, :credit, :debit with descriptions" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      names = Enum.map(ash_data.actions, & &1.name)
      assert :create in names
      assert :credit in names
      assert :debit in names
      credit = Enum.find(ash_data.actions, &(&1.name == :credit))
      assert String.contains?(credit.description, "LedgerEntry")
    end

    test "wallet attributes, relationships, and actions are plain maps (no raw structs)" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      Enum.each(ash_data.attributes, &refute(is_struct(&1)))
      Enum.each(ash_data.relationships, &refute(is_struct(&1)))
      Enum.each(ash_data.actions, &refute(is_struct(&1)))
    end

    test "all fields return appropriate defaults for empty structures" do
      {:ok, state} = SparkMeta.Walker.walk(IgamingRef.Finance.Wallet)
      ash_data = state.extension_data[Ash.Resource.Dsl]
      assert is_list(ash_data.compliance)
      assert is_list(ash_data.telemetry_prefix)
      assert is_list(ash_data.policies)
    end
  end
end
