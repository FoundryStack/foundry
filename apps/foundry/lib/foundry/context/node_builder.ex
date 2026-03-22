defmodule Foundry.Context.NodeBuilder do
  @moduledoc """
  Builds a NodeEntry from SparkMeta.ModuleInfo and project manifest.
  """

  alias Foundry.SparkMeta.ModuleInfo
  alias Foundry.Context.NodeEntry

  @spec build(ModuleInfo.t(), manifest :: keyword(), pending_migrations :: boolean()) ::
          NodeEntry.t()
  def build(%ModuleInfo{} = info, manifest, pending_migrations) do
    sensitive_modules = Keyword.get(manifest, :sensitive_resources, [])

    %NodeEntry{
      id: inspect(info.module),
      module: inspect(info.module),
      type: to_string(info.type || :resource),
      domain: derive_domain(info.module),
      app: nil,
      sensitive: info.module in sensitive_modules,
      description: info.description,
      attributes: info.attributes,
      actions: info.actions,
      rules: info.rules,
      compliance: info.compliance,
      adrs: info.adrs,
      runbook: info.runbook,
      test_coverage: %{property_tests: false, scenario_tests: false, e2e_tests: false},
      data_layer: info.data_layer,
      pending_migrations: pending_migrations,
      paper_trail: info.paper_trail,
      archival: info.archival,
      state_machine: info.state_machine,
      api_routes: info.api_routes,
      telemetry_prefix: info.telemetry_prefix,
      money_attributes: info.money_attributes,
      authentication_subject: info.authentication_subject,
      oban_queues: info.oban_queues,
      rate_limited: info.rate_limited,
      feature_flags: info.feature_flags,
      steps: info.steps,
      outputs: info.outputs,
      agent_steps: info.agent_steps,
      last_modified: format_mtime(info.last_modified)
    }
  end

  defp format_mtime(nil), do: nil

  defp format_mtime({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{String.pad_leading(to_string(month), 2, "0")}-#{String.pad_leading(to_string(day), 2, "0")} #{String.pad_leading(to_string(hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}:#{String.pad_leading(to_string(second), 2, "0")}"
  end

  defp format_mtime(other), do: other

  defp derive_domain(module) do
    # "IgamingRef.Finance.Wallet" → "Finance"
    module |> Module.split() |> Enum.drop(1) |> List.first() |> to_string()
  end
end
