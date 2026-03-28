defmodule Foundry.Context.GraphBuilderTest do
  use ExUnit.Case, async: false
  @moduletag :graph_builder

  setup_all do
    # Load reference project - find it relative to project root
    ref_root =
      __DIR__
      |> Path.split()
      |> Enum.take_while(&(&1 != "apps"))
      |> Path.join()
      |> Path.join("reference_projects/igaming")

    test_path = Path.join(ref_root, "_build/test/lib/igaming_ref/ebin")
    dev_path = Path.join(ref_root, "_build/dev/lib/igaming_ref/ebin")

    :code.add_path(String.to_charlist(test_path))
    :code.add_path(String.to_charlist(dev_path))

    {:ok, manifest} = Foundry.Manifest.Parser.read(ref_root)
    {nodes, edges} = Foundry.Context.GraphBuilder.build(ref_root, manifest)
    {:ok, nodes: nodes, edges: edges, node_map: Map.new(nodes, &{&1.module, &1})}
  end

  # Bug 1: field propagation - relationships
  test "Wallet has relationships", %{node_map: nm} do
    wallet = nm["IgamingRef.Finance.Wallet"]
    assert wallet != nil
    assert is_list(wallet.relationships)
    assert length(wallet.relationships) > 0
  end

  # Bug 1: field propagation - auth_strategies
  test "User has auth_strategies", %{node_map: nm} do
    user = nm["IgamingRef.Accounts.User"]
    assert user != nil
    assert is_list(user.auth_strategies)
    assert length(user.auth_strategies) > 0
  end

  # Bug 2: reactor steps inclusion
  test "ProviderSyncReactor has steps", %{node_map: nm} do
    reactor = nm["IgamingRef.Gaming.ProviderSyncReactor"]
    assert reactor != nil
    assert is_list(reactor.steps)
    assert length(reactor.steps) > 0
  end

  # Bug 3: @performs attribute registration
  test "CatalogSyncJob.performs is set", %{node_map: nm} do
    job = nm["IgamingRef.Gaming.CatalogSyncJob"]
    assert job != nil
    assert job.performs == "IgamingRef.Gaming.ProviderSyncReactor"
  end

  # Relationship edges: Wallet → Player (references)
  test "Wallet→Player references edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.Wallet", "IgamingRef.Players.Player", :references)
  end

  # Relationship edges: Wallet → LedgerEntry (referenced_by)
  test "Wallet→LedgerEntry referenced_by edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.Wallet", "IgamingRef.Finance.LedgerEntry", :referenced_by)
  end

  # Relationship edges: Wallet → WithdrawalRequest (referenced_by)
  test "Wallet→WithdrawalRequest referenced_by edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.Wallet", "IgamingRef.Finance.WithdrawalRequest", :referenced_by)
  end

  # Relationship edges: Player → Wallet (referenced_by)
  test "Player→Wallet referenced_by edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Players.Player", "IgamingRef.Finance.Wallet", :referenced_by)
  end

  # Relationship edges: Player → WithdrawalRequest (referenced_by)
  test "Player→WithdrawalRequest referenced_by edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Players.Player", "IgamingRef.Finance.WithdrawalRequest", :referenced_by)
  end

  # Relationship edges: LedgerEntry → Wallet (references)
  test "LedgerEntry→Wallet references edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.LedgerEntry", "IgamingRef.Finance.Wallet", :references)
  end

  # Relationship edges: WithdrawalRequest → Player (references)
  test "WithdrawalRequest→Player references edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.WithdrawalRequest", "IgamingRef.Players.Player", :references)
  end

  # Relationship edges: WithdrawalRequest → Wallet (references)
  test "WithdrawalRequest→Wallet references edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.WithdrawalRequest", "IgamingRef.Finance.Wallet", :references)
  end

  # Auth edge: User → Token (authenticates)
  test "User→Token authenticates edge exists", %{edges: edges} do
    assert Enum.any?(edges, fn edge ->
      edge.from == "IgamingRef.Accounts.User" and edge.relation == :authenticates
    end)
  end

  # Async edge: CatalogSyncJob → ProviderSyncReactor
  test "CatalogSyncJob→ProviderSyncReactor async edge exists", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Gaming.CatalogSyncJob", "IgamingRef.Gaming.ProviderSyncReactor", :async)
  end

  # Total edge sanity check: should have at least 20 edges with fixes
  test "at least 20 edges total", %{edges: edges} do
    assert length(edges) >= 20
  end

  # Check that edges are well-formed
  test "all edges have required fields", %{edges: edges} do
    Enum.each(edges, fn edge ->
      assert edge.from != nil, "Edge has nil from"
      assert edge.to != nil, "Edge has nil to"
      assert edge.relation != nil, "Edge has nil relation"
    end)
  end

  # Part A1: Rule edge derivation - "Applied by:" parsing
  test "SufficientBalance guards WithdrawalTransfer", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.Rules.SufficientBalance", "IgamingRef.Finance.WithdrawalTransfer", :guards)
  end

  test "WithdrawalLimitNotExceeded guards WithdrawalTransfer", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded", "IgamingRef.Finance.WithdrawalTransfer", :guards)
  end

  test "PlayerNotSelfExcluded guards WithdrawalTransfer", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Players.Rules.PlayerNotSelfExcluded", "IgamingRef.Finance.WithdrawalTransfer", :guards)
  end

  test "PlayerNotSelfExcluded guards BonusGrantTransfer", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Players.Rules.PlayerNotSelfExcluded", "IgamingRef.Promotions.BonusGrantTransfer", :guards)
  end

  test "PlayerEligibleForCampaign guards BonusGrantTransfer", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Promotions.Rules.PlayerEligibleForCampaign", "IgamingRef.Promotions.BonusGrantTransfer", :guards)
  end

  test "CampaignNotExpired guards BonusGrantTransfer", %{edges: edges} do
    assert find_edge(edges, "IgamingRef.Promotions.Rules.CampaignNotExpired", "IgamingRef.Promotions.BonusGrantTransfer", :guards)
  end

  test "PlayerKYCVerified is a rule node", %{node_map: nm} do
    kyc = nm["IgamingRef.Finance.Rules.PlayerKYCVerified"]
    assert kyc != nil
    assert kyc.type == "rule"
  end

  test "ProviderActive is a rule node", %{node_map: nm} do
    active = nm["IgamingRef.Gaming.Rules.ProviderActive"]
    assert active != nil
    assert active.type == "rule"
  end

  # Part A4: Per-domain external postgres nodes
  test "Finance resources connect to external:postgres:Finance", %{edges: edges} do
    wallet_postgres = Enum.any?(edges, fn edge ->
      edge.from == "IgamingRef.Finance.Wallet" and
      edge.to == "external:postgres:Finance" and
      edge.relation == :persists_to
    end)
    assert wallet_postgres, "Wallet should have persists_to edge to external:postgres:Finance"
  end

  test "Players resources connect to external:postgres:Players", %{edges: edges} do
    player_postgres = Enum.any?(edges, fn edge ->
      edge.from == "IgamingRef.Players.Player" and
      edge.to == "external:postgres:Players" and
      edge.relation == :persists_to
    end)
    assert player_postgres, "Player should have persists_to edge to external:postgres:Players"
  end

  test "Promotions resources connect to external:postgres:Promotions", %{edges: edges} do
    campaign_postgres = Enum.any?(edges, fn edge ->
      edge.from == "IgamingRef.Promotions.BonusCampaign" and
      edge.to == "external:postgres:Promotions" and
      edge.relation == :persists_to
    end)
    assert campaign_postgres, "BonusCampaign should have persists_to edge to external:postgres:Promotions"
  end

  test "no single external:postgres node exists (deprecated)", %{nodes: nodes} do
    single_postgres = Enum.find(nodes, fn node ->
      node.module == "external:postgres"
    end)
    assert single_postgres == nil, "Single external:postgres node should not exist; use per-domain instead"
  end

  test "external:postgres:Finance node exists", %{nodes: nodes} do
    postgres_finance = Enum.find(nodes, fn node ->
      node.module == "external:postgres:Finance"
    end)
    assert postgres_finance != nil
    assert postgres_finance.type == "external"
  end

  # Part A3: Provider adapter connections
  test "PragmaticPlayV1 provider node exists", %{node_map: nm} do
    provider = nm["IgamingRef.Gaming.Adapters.PragmaticPlayV1"]
    assert provider != nil
    assert provider.type == "provider"
  end

  test "PragmaticPlayV1 has calls_provider edge to external system", %{edges: edges} do
    provider_edge = Enum.any?(edges, fn edge ->
      edge.from == "IgamingRef.Gaming.Adapters.PragmaticPlayV1" and
      String.contains?(edge.to, "external:") and
      edge.relation == :calls_provider
    end)
    assert provider_edge, "Provider should have calls_provider edge to external system"
  end

  # Helper to find an edge
  defp find_edge(edges, from, to, relation) do
    Enum.any?(edges, fn edge ->
      edge.from == from and edge.to == to and edge.relation == relation
    end)
  end
end
