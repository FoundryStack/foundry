defmodule Foundry.PageMetadataTest do
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
          "ash_oban",
          "phoenix_live_view"
        ] do
      path = Path.join([@igaming_root, dep, "ebin"])
      if File.dir?(path), do: :code.add_path(String.to_charlist(path))
    end

    modules = [
      IgamingRef.Web.DepositLive,
      IgamingRef.Web.GameLive,
      IgamingRef.Web.HomeLive,
      IgamingRef.Web.AuthLive,
      Foundry.TestSupport.ExplicitRouteLive
    ]

    Enum.each(modules, &Code.ensure_loaded/1)
    :ok
  end

  test "static SDUI pages infer route from source when router data is unavailable" do
    deposit = Foundry.PageMetadata.analyze(IgamingRef.Web.DepositLive)
    home = Foundry.PageMetadata.analyze(IgamingRef.Web.HomeLive)

    assert deposit.page_route == "/deposit"
    assert deposit.page_dynamic == false
    assert home.page_route == "/"
    assert home.page_dynamic == false
  end

  test "dynamic SDUI lookup does not invent a route without router data" do
    game = Foundry.PageMetadata.analyze(IgamingRef.Web.GameLive)

    assert game.page_route == nil
    assert game.page_dynamic == false
  end

  test "explicit page_route still works as an escape hatch without router data" do
    info = Foundry.PageMetadata.analyze(Foundry.TestSupport.ExplicitRouteLive)

    assert info.page_route == "/support/explicit"
    assert info.page_dynamic == false
  end

  test "actions are inferred from AST without persisted @calls_actions annotations" do
    home = Foundry.PageMetadata.analyze(IgamingRef.Web.HomeLive)

    assert %{"resource" => "IgamingRef.Gaming.Game", "action" => :read, "action_name" => "read"} in home.calls_actions

    assert %{
             "resource" => "IgamingRef.Promotions.BonusCampaign",
             "action" => :read,
             "action_name" => "read"
           } in home.calls_actions
  end

  test "plain LiveView routes are not guessed from Ash action calls" do
    auth = Foundry.PageMetadata.analyze(IgamingRef.Web.AuthLive)

    assert auth.page_route == nil
    assert auth.page_dynamic == false

    assert %{"resource" => "IgamingRef.Accounts.Token", "action" => :write} =
             Enum.at(auth.calls_actions, 0)
  end

  test "SparkMeta carries inferred page route and calls_actions for static pages" do
    info = Foundry.SparkMeta.walk(IgamingRef.Web.DepositLive)

    assert info.page_route == "/deposit"
    assert info.page_dynamic == false

    assert Enum.any?(info.calls_actions, fn action ->
             action["resource"] == "IgamingRef.Finance.Wallet" and action["action"] == :read
           end)

    assert Enum.any?(info.calls_actions, fn action ->
             action["resource"] == "IgamingRef.Finance.Transfer" and
               action["action_name"] == "record"
           end)
  end
end
