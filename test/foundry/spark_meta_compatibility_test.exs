defmodule Foundry.SparkMetaCompatibilityTest do
  use ExUnit.Case, async: false

  @igaming_root Path.expand("../../../../reference_projects/igaming/_build/dev/lib", __DIR__)

  setup_all do
    :code.add_path(String.to_charlist(Path.join([@igaming_root, "igaming_ref", "ebin"])))

    for dep <- [
          "ash_state_machine",
          "ash_paper_trail",
          "ash_archival",
          "ash_postgres",
          "ash_authentication",
          "ash_oban"
        ] do
      path = Path.join([@igaming_root, dep, "ebin"])
      if File.dir?(path), do: :code.add_path(String.to_charlist(path))
    end

    modules = [
      IgamingRef.Finance.Wallet,
      IgamingRef.Gaming.ProviderSyncReactor,
      IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook,
      IgamingRef.Finance.WithdrawalWebhook,
      IgamingRef.Finance.Rules.SufficientBalance,
      IgamingRef.Accounts.User
    ]

    Enum.each(modules, &Code.ensure_loaded/1)
    :ok
  end

  test "resource modules preserve resource facts while omitting graph-owned relationships" do
    info = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)

    assert info.type == :resource
    assert Enum.any?(info.attributes, &(&1.name == :balance))
    assert info.relationships == []
    assert "RG_MGA_001" in info.compliance
    assert info.diagnostics == []
  end

  test "resource modules infer state machine transitions with action names" do
    info = Foundry.SparkMeta.walk(IgamingRef.Finance.Wallet)

    assert info.state_machine.present == true
    assert "active" in info.state_machine.states
    assert "frozen" in info.state_machine.states
    assert "closed" in info.state_machine.states

    assert Enum.any?(info.state_machine.transitions, fn transition ->
             transition[:from] == "active" and
               transition[:to] == "frozen" and
               transition[:action] == "freeze"
           end)

    assert Enum.any?(info.state_machine.transitions, fn transition ->
             transition[:from] == "active" and
               transition[:to] == "closed" and
               transition[:action] == "close"
           end)

    assert Enum.any?(info.state_machine.transitions, fn transition ->
             transition[:from] == "frozen" and
               transition[:to] == "closed" and
               transition[:action] == "close"
           end)
  end

  test "reactor modules preserve runbook and step facts" do
    info = Foundry.SparkMeta.walk(IgamingRef.Gaming.ProviderSyncReactor)

    assert info.type == :reactor
    assert info.runbook == "docs/runbooks/provider_sync.md"
    assert length(info.steps) == 4
    assert Enum.any?(info.steps, &(&1.name == :load_provider and &1.step_kind == :read))
  end

  test "trace metadata strings do not leak short resource aliases into reactor facts" do
    info = Foundry.SparkMeta.walk(IgamingRef.Promotions.BonusGrantTransfer)

    load_context = Enum.find(info.steps, &(&1.name == :load_context))
    assert load_context

    assert "IgamingRef.Players.Player" in load_context.read_targets
    refute "Player" in load_context.read_targets
    refute load_context.target_resource == "Player"
  end

  test "oban workers preserve queue and performs metadata" do
    info = Foundry.SparkMeta.walk(IgamingRef.Finance.Jobs.ProcessWithdrawalWebhook)

    assert info.type == :job
    assert info.oban_queues == ["default"]
    assert info.performs == "IgamingRef.Finance.WithdrawalRequest"
  end

  test "trigger modules preserve trigger kind and inferred side effects" do
    info = Foundry.SparkMeta.walk(IgamingRef.Finance.WithdrawalWebhook)

    assert info.type == :trigger
    assert info.trigger_kind == "webhook"
    assert Enum.any?(info.side_effects, &(&1.type == :oban_emit))
  end

  test "rule modules keep the full rule moduledoc description" do
    info = Foundry.SparkMeta.walk(IgamingRef.Finance.Rules.SufficientBalance)

    assert info.type == :rule
    assert info.description =~ "Applied by: IgamingRef.Finance.WithdrawalTransfer"
  end

  test "authentication resources omit graph-owned auth strategy extraction" do
    info = Foundry.SparkMeta.walk(IgamingRef.Accounts.User)

    assert info.authentication_subject == true
    assert info.auth_strategies == []
  end

  test "token resources are not classified as authentication subjects" do
    info = Foundry.SparkMeta.walk(IgamingRef.Accounts.Token)

    assert info.authentication_subject == false
    assert info.auth_strategies == []
  end
end
