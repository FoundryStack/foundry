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
end
