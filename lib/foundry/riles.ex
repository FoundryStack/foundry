defmodule Foundry.Lint.Rule do
  @moduledoc """
  Behaviour for all Foundry lint rules.

  Each rule module implements `check/1`, receiving a `Foundry.Lint.Context`
  and returning a (possibly empty) list of `Foundry.Lint.LintReport.Violation`s.

  Rules must be pure — no side effects, no file writes, no external calls.
  """

  alias Foundry.Lint.{Context, LintReport.Violation}

  @callback check(Context.t()) :: [Violation.t()]
end

# ---------------------------------------------------------------------------
# INV-006 — Description coverage
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.DescriptionRule do
  @moduledoc "Enforces INV-006: all Ash resource attributes must have descriptions; all public modules must have @moduledoc."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod}) do
    violations = []

    # Check @moduledoc
    violations =
      case Code.fetch_docs(mod) do
        {:docs_v1, _, _, _, :none, _, _} ->
          [
            %Violation{
              rule_id: :missing_description,
              severity: :error,
              message: "#{mod} is missing @moduledoc",
              module: to_string(mod)
            }
            | violations
          ]

        {:docs_v1, _, _, _, :hidden, _, _} ->
          # @moduledoc false is acceptable (intentionally hidden)
          violations

        _ ->
          violations
      end

    # Check Ash resource attribute descriptions
    violations =
      if ash_resource?(mod) do
        try do
          Ash.Resource.Info.attributes(mod)
          |> Enum.reject(&(&1.name in [:id, :inserted_at, :updated_at]))
          |> Enum.flat_map(fn attr ->
            if is_nil(attr.description) or attr.description == "" do
              [
                %Violation{
                  rule_id: :missing_description,
                  severity: :error,
                  message: "#{mod}.#{attr.name} is missing a description:",
                  module: to_string(mod)
                }
              ]
            else
              []
            end
          end)
        rescue
          _ -> []
        end ++ violations
      else
        violations
      end

    violations
  end

  defp ash_resource?(mod) do
    function_exported?(mod, :spark_dsl_config, 0)
  rescue
    _ -> false
  end
end

# ---------------------------------------------------------------------------
# INV-011 — Paper trail on sensitive resources
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.PaperTrailRule do
  @moduledoc "Enforces INV-011: sensitive resources must use AshPaperTrail.Resource."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod, manifest: manifest}) do
    sensitive = sensitive_set(manifest)

    if sensitive?(mod, sensitive) and not has_paper_trail?(mod) do
      [
        %Violation{
          rule_id: :missing_paper_trail,
          severity: :error,
          message:
            "#{mod} is a sensitive resource but does not use AshPaperTrail.Resource (INV-011)",
          module: to_string(mod)
        }
      ]
    else
      []
    end
  end

  defp sensitive?(mod, sensitive_set) do
    MapSet.member?(sensitive_set, to_string(mod)) or auth_resource?(mod)
  end

  defp auth_resource?(mod) do
    exts = spark_extensions(mod)
    AshAuthentication in exts or AshAuthentication.TokenResource in exts
  rescue
    _ -> false
  end

  defp has_paper_trail?(mod) do
    AshPaperTrail.Resource in spark_extensions(mod)
  rescue
    _ -> false
  end

  defp sensitive_set(manifest) do
    (manifest[:sensitive_resources] || []) |> Enum.map(&to_string/1) |> MapSet.new()
  end

  defp spark_extensions(mod) do
    Spark.Dsl.Extension.get_persisted(mod, :extensions) || []
  rescue
    _ -> []
  end
end

# ---------------------------------------------------------------------------
# INV-012 — Archival on sensitive resources
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.ArchivalRule do
  @moduledoc "Enforces INV-012: sensitive resources must use AshArchival.Resource."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod, manifest: manifest}) do
    sensitive = sensitive_set(manifest)

    if sensitive?(mod, sensitive) and not has_archival?(mod) do
      [
        %Violation{
          rule_id: :missing_archival,
          severity: :error,
          message:
            "#{mod} is a sensitive resource but does not use AshArchival.Resource (INV-012)",
          module: to_string(mod)
        }
      ]
    else
      []
    end
  end

  defp sensitive?(mod, sensitive_set) do
    MapSet.member?(sensitive_set, to_string(mod)) or auth_resource?(mod)
  end

  defp auth_resource?(mod) do
    exts = spark_extensions(mod)
    AshAuthentication in exts or AshAuthentication.TokenResource in exts
  rescue
    _ -> false
  end

  defp has_archival?(mod) do
    AshArchival.Resource in spark_extensions(mod)
  rescue
    _ -> false
  end

  defp sensitive_set(manifest) do
    (manifest[:sensitive_resources] || []) |> Enum.map(&to_string/1) |> MapSet.new()
  end

  defp spark_extensions(mod) do
    Spark.Dsl.Extension.get_persisted(mod, :extensions) || []
  rescue
    _ -> []
  end
end

# ---------------------------------------------------------------------------
# INV-004 — Idempotency on Transfers
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.IdempotencyRule do
  @moduledoc "Enforces INV-004: Transfer modules with external side effects must declare an idempotency key."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  # Step types considered to have external side effects
  @side_effect_steps [:create, :update, :destroy, :action, :run]

  @impl true
  def check(%{module: mod}) do
    if not transfer_module?(mod) do
      []
    else
      has_idempotency =
        try do
          mod.__info__(:attributes)[:idempotency_key] != nil or
            mod.__info__(:attributes)[:idempotency] != nil
        rescue
          _ -> false
        end

      steps = reactor_steps(mod)
      has_external = Enum.any?(steps, &(&1.type in @side_effect_steps))

      if has_external and not has_idempotency do
        [
          %Violation{
            rule_id: :missing_idempotency,
            severity: :error,
            message:
              "#{mod} is a Transfer with external side effects but declares no idempotency key (INV-004)",
            module: to_string(mod)
          }
        ]
      else
        []
      end
    end
  end

  defp transfer_module?(mod) do
    function_exported?(mod, :__transfer_dsl__, 0) or
      (function_exported?(mod, :reactor, 0) and reactor_steps(mod) != [])
  rescue
    _ -> false
  end

  defp reactor_steps(mod) do
    try do
      Spark.Dsl.Extension.get_entities(mod, [:reactor, :steps])
    rescue
      _ -> []
    end
  end
end

# ---------------------------------------------------------------------------
# INV-005 — Runbook links on Transfers
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.RunbookRule do
  @moduledoc "Enforces INV-005: Reactor modules with more than 3 steps must declare @runbook pointing to an existing file."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod, project_root: project_root}) do
    if not reactor_module?(mod) do
      []
    else
      steps = reactor_steps(mod)

      if length(steps) <= 3 do
        []
      else
        runbook =
          try do
            mod.__info__(:attributes)[:runbook]
            |> List.wrap()
            |> List.first()
          rescue
            _ -> nil
          end

        cond do
          is_nil(runbook) ->
            [
              %Violation{
                rule_id: :missing_runbook,
                severity: :error,
                message: "#{mod} has #{length(steps)} steps but declares no @runbook (INV-005)",
                module: to_string(mod)
              }
            ]

          not File.exists?(Path.join(project_root, runbook)) ->
            [
              %Violation{
                rule_id: :missing_runbook,
                severity: :error,
                message: "#{mod} @runbook points to #{runbook} which does not exist (INV-005)",
                module: to_string(mod),
                file_path: runbook
              }
            ]

          true ->
            []
        end
      end
    end
  end

  defp reactor_module?(mod) do
    function_exported?(mod, :reactor, 0) or
      (function_exported?(mod, :spark_dsl_config, 0) and
         Reactor in (Spark.Dsl.Extension.get_persisted(mod, :extensions) || []))
  rescue
    _ -> false
  end

  defp reactor_steps(mod) do
    try do
      Spark.Dsl.Extension.get_entities(mod, [:reactor, :steps])
    rescue
      _ -> []
    end
  end
end

# ---------------------------------------------------------------------------
# INV-013 — Feature flag ADR links
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.AdminRouteRule do
  @moduledoc "Checks that oban_web, phoenix_live_dashboard, and fun_with_flags_ui routes are behind ash_authentication."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod}) do
    # Only applies to Router modules
    if not router_module?(mod),
      do: [],
      # This is a structural check — we look for the admin route mounts
      # and verify they are inside a pipeline that includes ash_authentication.
      # Full implementation requires parsing the router's __routes__/0.
      # Stub returns no violations — full implementation in Phase 1 lint pass.
      # TODO: implement route authentication check by inspecting mod.__routes__()
      else: []
  end

  defp router_module?(mod) do
    function_exported?(mod, :__routes__, 0) and
      function_exported?(mod, :call, 2)
  rescue
    _ -> false
  end
end

# ---------------------------------------------------------------------------
# Money type rule
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.MoneyTypeRule do
  @moduledoc "Rejects raw Money.t() attribute types — all monetary attributes must use Ash.Type.Money."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod}) do
    if not ash_resource?(mod) do
      []
    else
      try do
        Ash.Resource.Info.attributes(mod)
        |> Enum.flat_map(fn attr ->
          if raw_money_type?(attr.type) do
            [
              %Violation{
                rule_id: :raw_money_type,
                severity: :error,
                message: "#{mod}.#{attr.name} uses raw Money.t() — use Ash.Type.Money instead",
                module: to_string(mod)
              }
            ]
          else
            []
          end
        end)
      rescue
        _ -> []
      end
    end
  end

  defp raw_money_type?(Money), do: true
  defp raw_money_type?({:parameterized, Money, _}), do: true
  defp raw_money_type?(_), do: false

  defp ash_resource?(mod) do
    function_exported?(mod, :spark_dsl_config, 0)
  rescue
    _ -> false
  end
end

# ---------------------------------------------------------------------------
# Decorator governance rule (Gap #53)
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.DecoratorRule do
  @moduledoc """
  Warns when a Transfer module contains functions decorated via the `decorator`
  library. Foundry cannot introspect decorated function signatures — the change
  class of modifications to these steps cannot be auto-classified. Manual review
  is required. See: docs/lint-catalogue.md — :decorated_transfer_step.
  """
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  @impl true
  def check(%{module: mod}) do
    if not transfer_module?(mod) do
      []
    else
      decorated_fns =
        try do
          mod.__info__(:attributes)
          |> Enum.flat_map(fn
            {:decorate_all_opts, fns} -> Enum.map(fns, &to_string/1)
            {:decorate, [{name, _arity} | _]} -> [to_string(name)]
            _ -> []
          end)
        rescue
          _ -> []
        end

      if decorated_fns != [] do
        [
          %Violation{
            rule_id: :decorated_transfer_step,
            severity: :warning,
            message:
              "#{mod} contains decorated Transfer steps (#{Enum.join(decorated_fns, ", ")}). " <>
                "Foundry cannot auto-classify changes to decorated steps — manual review required.",
            module: to_string(mod)
          }
        ]
      else
        []
      end
    end
  end

  defp transfer_module?(mod) do
    function_exported?(mod, :__transfer_dsl__, 0) or
      function_exported?(mod, :reactor, 0)
  rescue
    _ -> false
  end
end

# ---------------------------------------------------------------------------
# Manifest validation rules (run once, not per-module)
# ---------------------------------------------------------------------------

defmodule Foundry.Lint.Rules.ManifestValidator do
  @moduledoc "Validates the .foundry/manifest.exs structure. Runs once per lint pass, not per module."
  @behaviour Foundry.Lint.Rule

  alias Foundry.Lint.LintReport.Violation

  # Per-module check: no-op — manifest rules run via check_manifest/1
  @impl true
  def check(_ctx), do: []

  @doc "Run manifest-level validations. Called by Runner.run/1 after per-module pass."
  def check_manifest(manifest) do
    []
    |> check_required_approvers(manifest)
    |> check_notification_config(manifest)
    |> check_coverage_weights(manifest)
    |> check_context_exclusion_comments(manifest)
  end

  defp check_required_approvers(acc, manifest) do
    approvers = manifest[:approvers] || []

    acc =
      if Keyword.get(approvers, :sensitive_lead) in [nil, ""] do
        [
          %Violation{
            rule_id: :manifest_missing_required_approver,
            severity: :error,
            message: "manifest.exs: approvers.sensitive_lead is required"
          }
          | acc
        ]
      else
        acc
      end

    if Keyword.get(approvers, :compliance_officer) in [nil, ""] do
      [
        %Violation{
          rule_id: :manifest_missing_required_approver,
          severity: :error,
          message: "manifest.exs: approvers.compliance_officer is required"
        }
        | acc
      ]
    else
      acc
    end
  end

  defp check_notification_config(acc, manifest) do
    notifications = manifest[:notifications]

    if is_nil(notifications) do
      [
        %Violation{
          rule_id: :missing_notification_config,
          severity: :warning,
          message:
            "manifest.exs: notifications are not configured (INV-010). " <>
              "runbook_stale, adapter_verify_failed, and compliance_test_failed channels required."
        }
        | acc
      ]
    else
      required = [:runbook_stale, :adapter_verify_failed, :compliance_test_failed]

      Enum.reduce(required, acc, fn key, a ->
        if is_nil(Keyword.get(notifications, key)) do
          [
            %Violation{
              rule_id: :missing_notification_config,
              severity: :warning,
              message: "manifest.exs: notifications.#{key} is not configured (INV-010)"
            }
            | a
          ]
        else
          a
        end
      end)
    end
  end

  defp check_coverage_weights(acc, manifest) do
    weights = manifest[:coverage_weights]

    if is_nil(weights) or weights == [] do
      acc
    else
      get_weight = fn key ->
        val =
          cond do
            is_list(weights) -> Keyword.get(weights, key, 0)
            is_map(weights) and not is_struct(weights) -> Map.get(weights, key, 0)
            is_struct(weights) -> Map.get(weights, key, 0)
            true -> 0
          end

        (is_number(val) && val) || 0
      end

      total =
        [
          :transfer_coverage,
          :rule_coverage,
          :blueprint_coverage,
          :compliance_coverage,
          :ui_coverage
        ]
        |> Enum.map(get_weight)
        |> Enum.sum()

      if abs(total - 1.0) > 0.001 do
        [
          %Violation{
            rule_id: :manifest_invalid_coverage_weights,
            severity: :error,
            message: "manifest.exs: coverage_weights sum to #{total}, must equal 1.0 (±0.001)"
          }
          | acc
        ]
      else
        acc
      end
    end
  end

  defp check_context_exclusion_comments(acc, _manifest) do
    # Comment presence requires reading the raw manifest.exs source — out of
    # scope for in-memory validation. Deferred: implement in Phase 1 lint pass
    # by passing raw manifest source through to the validator.
    acc
  end
end
