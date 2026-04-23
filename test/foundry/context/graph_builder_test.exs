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

  test "Wallet no longer carries relationship payload on the node", %{node_map: nm} do
    wallet = nm["IgamingRef.Finance.Wallet"]
    assert wallet != nil
    assert wallet.relationships == []
  end

  test "User no longer carries auth strategy payload on the node", %{node_map: nm} do
    user = nm["IgamingRef.Accounts.User"]
    assert user != nil
    assert user.auth_strategies == []
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
    assert find_edge(
             edges,
             "IgamingRef.Finance.Wallet",
             "IgamingRef.Finance.LedgerEntry",
             :referenced_by
           )
  end

  # Relationship edges: Wallet → WithdrawalRequest (referenced_by)
  test "Wallet→WithdrawalRequest referenced_by edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.Wallet",
             "IgamingRef.Finance.WithdrawalRequest",
             :referenced_by
           )
  end

  # Relationship edges: Player → Wallet (referenced_by)
  test "Player→Wallet referenced_by edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Players.Player",
             "IgamingRef.Finance.Wallet",
             :referenced_by
           )
  end

  # Relationship edges: Player → WithdrawalRequest (referenced_by)
  test "Player→WithdrawalRequest referenced_by edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Players.Player",
             "IgamingRef.Finance.WithdrawalRequest",
             :referenced_by
           )
  end

  # Relationship edges: LedgerEntry → Wallet (references)
  test "LedgerEntry→Wallet references edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.LedgerEntry",
             "IgamingRef.Finance.Wallet",
             :references
           )
  end

  # Relationship edges: WithdrawalRequest → Player (references)
  test "WithdrawalRequest→Player references edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalRequest",
             "IgamingRef.Players.Player",
             :references
           )
  end

  # Relationship edges: WithdrawalRequest → Wallet (references)
  test "WithdrawalRequest→Wallet references edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalRequest",
             "IgamingRef.Finance.Wallet",
             :references
           )
  end

  # Auth edge: User → Token (authenticates)
  test "User→Token authenticates edge exists", %{edges: edges} do
    assert Enum.any?(edges, fn edge ->
             edge.from == "IgamingRef.Accounts.User" and edge.relation == :authenticates
           end)
  end

  # Async edge: CatalogSyncJob → ProviderSyncReactor
  test "CatalogSyncJob→ProviderSyncReactor async edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Gaming.CatalogSyncJob",
             "IgamingRef.Gaming.ProviderSyncReactor",
             :async
           )
  end

  test "WithdrawalTransfer reads WithdrawalRequest, Wallet, and Player", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalTransfer",
             "IgamingRef.Finance.WithdrawalRequest",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalTransfer",
             "IgamingRef.Finance.Wallet",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalTransfer",
             "IgamingRef.Players.Player",
             :reads
           )
  end

  test "WithdrawalTransfer writes Wallet, LedgerEntry, and WithdrawalRequest", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalTransfer",
             "IgamingRef.Finance.Wallet",
             :writes
           )

    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalTransfer",
             "IgamingRef.Finance.LedgerEntry",
             :writes
           )

    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalTransfer",
             "IgamingRef.Finance.WithdrawalRequest",
             :writes
           )
  end

  test "BonusGrantTransfer reads Player, BonusCampaign, Wallet, and BonusGrant", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Players.Player",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Promotions.BonusCampaign",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Finance.Wallet",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Promotions.BonusGrant",
             :reads
           )
  end

  test "BonusGrantTransfer writes Wallet, LedgerEntry, and BonusGrant", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Finance.Wallet",
             :writes
           )

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Finance.LedgerEntry",
             :writes
           )

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusGrantTransfer",
             "IgamingRef.Promotions.BonusGrant",
             :writes
           )
  end

  test "ProviderSyncReactor reads ProviderConfig and writes Game", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Gaming.ProviderSyncReactor",
             "IgamingRef.Gaming.ProviderConfig",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Gaming.ProviderSyncReactor",
             "IgamingRef.Gaming.Game",
             :writes
           )
  end

  test "BonusEvaluationReactor reads and writes BonusEvent", %{edges: edges, node_map: nm} do
    reactor = nm["IgamingRef.Promotions.BonusEvaluationReactor"]
    assert reactor != nil
    assert reactor.type == "reactor"

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusEvaluationReactor",
             "IgamingRef.Promotions.BonusEvent",
             :reads
           )

    assert find_edge(
             edges,
             "IgamingRef.Promotions.BonusEvaluationReactor",
             "IgamingRef.Promotions.BonusEvent",
             :writes
           )
  end

  test "behavioral edges carry step metadata", %{edges: edges} do
    load_request =
      find_edge_entry(
        edges,
        "IgamingRef.Finance.WithdrawalTransfer",
        "IgamingRef.Finance.WithdrawalRequest",
        :reads,
        "load_request"
      )

    assert load_request.step_name == "load_request"
    assert is_integer(load_request.step_index)

    debit_wallet =
      find_edge_entry(
        edges,
        "IgamingRef.Finance.WithdrawalTransfer",
        "IgamingRef.Finance.Wallet",
        :writes,
        "debit_wallet"
      )

    assert debit_wallet.step_name == "debit_wallet"
    assert is_integer(debit_wallet.step_index)

    create_ledger_entry =
      find_edge_entry(
        edges,
        "IgamingRef.Finance.WithdrawalTransfer",
        "IgamingRef.Finance.LedgerEntry",
        :writes,
        "create_ledger_entry"
      )

    assert create_ledger_entry.step_name == "create_ledger_entry"
    assert is_integer(create_ledger_entry.step_index)

    load_provider =
      find_edge_entry(
        edges,
        "IgamingRef.Gaming.ProviderSyncReactor",
        "IgamingRef.Gaming.ProviderConfig",
        :reads,
        "load_provider"
      )

    assert load_provider.step_name == "load_provider"
    assert is_integer(load_provider.step_index)

    sync_games =
      find_edge_entry(
        edges,
        "IgamingRef.Gaming.ProviderSyncReactor",
        "IgamingRef.Gaming.Game",
        :writes,
        "sync_games"
      )

    assert sync_games.step_name == "sync_games"
    assert is_integer(sync_games.step_index)
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

  test "reactor and transfer guard edges are inferred from source rule calls", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.Rules.SufficientBalance",
             "IgamingRef.Finance.WithdrawalTransfer",
             :guards
           )

    assert find_edge(
             edges,
             "IgamingRef.Finance.Rules.WithdrawalLimitNotExceeded",
             "IgamingRef.Finance.WithdrawalTransfer",
             :guards
           )

    assert find_edge(
             edges,
             "IgamingRef.Finance.Rules.PlayerKYCVerified",
             "IgamingRef.Finance.WithdrawalTransfer",
             :guards
           )

    assert find_edge(
             edges,
             "IgamingRef.Players.Rules.PlayerNotSelfExcluded",
             "IgamingRef.Finance.WithdrawalTransfer",
             :guards
           )

    assert find_edge(
             edges,
             "IgamingRef.Players.Rules.PlayerNotSelfExcluded",
             "IgamingRef.Promotions.BonusGrantTransfer",
             :guards
           )
  end

  test "AuthenticatedSubject guards Wallet via policy DSL", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Policies.AuthenticatedSubject",
             "IgamingRef.Finance.Wallet",
             :guards
           )
  end

  test "ComplianceOrPlatformLead guards Wallet via policy DSL", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Policies.ComplianceOrPlatformLead",
             "IgamingRef.Finance.Wallet",
             :guards
           )
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

  test "rule usage comes from executable source, not comments", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.Rules.PlayerKYCVerified",
             "IgamingRef.Finance.WithdrawalTransfer",
             :guards
           )

    assert find_edge(
             edges,
             "IgamingRef.Gaming.Rules.ProviderActive",
             "IgamingRef.Gaming.ProviderSyncReactor",
             :guards
           )

    refute find_edge(
             edges,
             "IgamingRef.Gaming.Rules.GameRTPCertified",
             "IgamingRef.Gaming.ProviderSyncReactor",
             :guards
           )
  end

  # Part A4: Per-domain external postgres nodes
  test "Finance resources connect to external:postgres:Finance", %{edges: edges} do
    wallet_postgres =
      Enum.any?(edges, fn edge ->
        edge.from == "IgamingRef.Finance.Wallet" and
          edge.to == "external:postgres:Finance" and
          edge.relation == :persists_to
      end)

    assert wallet_postgres, "Wallet should have persists_to edge to external:postgres:Finance"
  end

  test "Players resources connect to external:postgres:Players", %{edges: edges} do
    player_postgres =
      Enum.any?(edges, fn edge ->
        edge.from == "IgamingRef.Players.Player" and
          edge.to == "external:postgres:Players" and
          edge.relation == :persists_to
      end)

    assert player_postgres, "Player should have persists_to edge to external:postgres:Players"
  end

  test "Promotions resources connect to external:postgres:Promotions", %{edges: edges} do
    campaign_postgres =
      Enum.any?(edges, fn edge ->
        edge.from == "IgamingRef.Promotions.BonusCampaign" and
          edge.to == "external:postgres:Promotions" and
          edge.relation == :persists_to
      end)

    assert campaign_postgres,
           "BonusCampaign should have persists_to edge to external:postgres:Promotions"
  end

  test "no single external:postgres node exists (deprecated)", %{nodes: nodes} do
    single_postgres =
      Enum.find(nodes, fn node ->
        node.module == "external:postgres"
      end)

    assert single_postgres == nil,
           "Single external:postgres node should not exist; use per-domain instead"
  end

  test "external:postgres:Finance node exists", %{nodes: nodes} do
    postgres_finance =
      Enum.find(nodes, fn node ->
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
    provider_edge =
      Enum.any?(edges, fn edge ->
        edge.from == "IgamingRef.Gaming.Adapters.PragmaticPlayV1" and
          String.contains?(edge.to, "external:") and
          edge.relation == :calls_provider
      end)

    assert provider_edge, "Provider should have calls_provider edge to external system"
  end

  test "WithdrawalWebhook is a trigger node", %{node_map: nm} do
    webhook = nm["IgamingRef.Finance.WithdrawalWebhook"]
    assert webhook != nil
    assert webhook.type == "trigger"
    assert webhook.trigger_kind == "webhook"
  end

  test "WithdrawalWebhook enqueues ProcessWithdrawalWebhook", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.WithdrawalWebhook",
             "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook",
             :enqueues
           )
  end

  test "ProcessWithdrawalWebhook async edge exists", %{edges: edges} do
    assert find_edge(
             edges,
             "IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook",
             "IgamingRef.Finance.WithdrawalRequest",
             :async
           )
  end

  # Helper to find an edge
  defp find_edge(edges, from, to, relation) do
    Enum.any?(edges, fn edge ->
      edge.from == from and edge.to == to and edge.relation == relation
    end)
  end

  defp find_edge_entry(edges, from, to, relation, step_name) do
    Enum.find(edges, fn edge ->
      edge.from == from and edge.to == to and edge.relation == relation and
        edge.step_name == step_name
    end)
  end
end
