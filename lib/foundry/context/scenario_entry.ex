defmodule Foundry.Context.ScenarioEntry do
  @moduledoc """
  A scenario is either a compliance-tagged test or a runtime trigger entry.

  Collected into `NodeEntry.scenario_origins`. Populated from compliance-tagged
  ExUnit tests (Layer 2 compliance scenarios) and, in Phase D, from runtime
  trigger extraction (cron schedules, Oban conditions, API routes, auth events).

  ## Usage

  Compliance test scenario:
      %ScenarioEntry{
        requirement_id: "RG-MGA-001",
        test_module: "IgamingRef.Compliance.MgaTest",
        test_tag: :rg_mga_001,
        status: :partial,
        description: "Verifies player spending limits are enforced"
      }

  Runtime trigger scenario (Phase D):
      %ScenarioEntry{
        trigger_type: :cron,
        schedule: "0 0 * * *",
        initiates_module: "MyApp.Finance.DailyReconciliation",
        description: "Daily ledger reconciliation at midnight"
      }
  """

  @type status :: :missing | :partial | :implemented
  @type trigger_type :: :cron | :oban_condition | :json_api | :graphql | :auth_event | nil

  defstruct [
    # Compliance test scenario (from compliance-tagged ExUnit tests)
    :requirement_id,
    :test_module,
    :test_tag,
    :trigger_type,
    :schedule,
    :condition_expr,
    :route_method,
    :route_path,
    :mutation_name,
    :initiates_module,
    :description,
    status: :missing
  ]
end
