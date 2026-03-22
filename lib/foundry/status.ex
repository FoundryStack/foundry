defmodule Foundry.Status do
  @moduledoc """
  Runtime health picture composed from all Phase 1 data.

  Assembles project status from:
  - Compilation state (compiled_at from .beam files)
  - Stack versions (from mix.lock)
  - Lint violations (from Foundry.Lint.Runner)
  - Migrations (pending count from Foundry.Manifest)
  - Proposals (open count from proposal storage)
  - Compliance matrix (from Foundry.Context.ProjectContext)
  - Test coverage (from project fixture)
  - CI state (from lock file and optional .foundry/ci_status.json)
  - Project manifest metadata
  """

  defstruct [
    :generated_at,
    :compiled_at,
    :project,
    :project_type,
    :domain_type,
    :domains,
    :sensitive_modules,
    :lint,
    :migrations,
    :proposals,
    :compliance,
    :test_coverage,
    :ci,
    :stack,
    :manifest
  ]

  def build(project_root) do
    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)

    domain_type = Keyword.get(manifest, :domain_type, "")
    domain_type_str = if is_atom(domain_type), do: Atom.to_string(domain_type), else: domain_type

    project_name = Keyword.get(manifest, :project_name, "")
    project_type = Keyword.get(manifest, :project_type, "standard")

    # Fetch all components
    {nodes, _edges} = Foundry.Context.GraphBuilder.build(project_root, manifest)
    lint_report = Foundry.Lint.Runner.run(project_root)
    stack_versions = Foundry.Status.StackVersions.read(project_root)
    compiled_at = compiled_at(project_root)

    # Extract domains from nodes
    domains = extract_domains(nodes)

    # Extract sensitive modules from nodes
    sensitive_modules = extract_sensitive_modules(nodes)

    # Build status structure
    %{
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "compiled_at" => compiled_at,
      "project" => project_name,
      "project_type" => project_type,
      "domain_type" => domain_type_str,
      "domains" => domains,
      "sensitive_modules" => sensitive_modules,
      "lint" => lint_to_status(lint_report),
      "migrations" => migrations_status(manifest),
      "proposals" => proposals_status(project_root),
      "compliance" => compliance_status(nodes),
      "test_coverage" => test_coverage_status(),
      "ci" => ci_status(project_root),
      "stack" => stack_versions,
      "manifest" => manifest_summary(manifest)
    }
  end

  defp compiled_at(project_root) do
    # Try to find .beam files in common build directories
    beam_files =
      [
        # Try looking for any .beam files in dev ebin
        Path.join([project_root, "_build", "dev", "lib", "*", "ebin", "*.beam"]),
        # Try looking for any .beam files in test ebin
        Path.join([project_root, "_build", "test", "lib", "*", "ebin", "*.beam"])
      ]
      |> Enum.flat_map(&Path.wildcard/1)

    case beam_files do
      [] ->
        nil

      beams ->
        beams
        |> Enum.map(&File.stat!(&1).mtime)
        |> Enum.max()
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_iso8601()
    end
  end

  defp extract_domains(nodes) do
    nodes
    |> Enum.map(& &1.domain)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_sensitive_modules(nodes) do
    nodes
    |> Enum.filter(& &1.sensitive)
    |> Enum.map(fn node ->
      # Extract short name from FQN: MyApp.Domain.Resource -> Resource
      node.module
      |> String.split(".")
      |> List.last()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp lint_to_status(lint_report) do
    %{
      "errors" => Enum.count(lint_report.violations, &(&1.severity == :error)),
      "warnings" => Enum.count(lint_report.violations, &(&1.severity == :warning)),
      "total_violations" => length(lint_report.violations)
    }
  end

  defp migrations_status(_manifest) do
    # TODO: Implement pending migration count from Foundry.Manifest
    # For now, return placeholder
    %{
      "pending_count" => 0,
      "applied_count" => 0
    }
  end

  defp proposals_status(project_root) do
    # TODO: Implement proposal count from storage
    # For now, return placeholder
    _ = project_root

    %{
      "open_count" => 0,
      "recent" => []
    }
  end

  defp compliance_status(nodes) do
    # Extract compliance requirements from nodes
    # Convert underscore format (RG_MGA_001) to hyphen format (RG-MGA-001)
    requirements =
      nodes
      |> Enum.flat_map(& &1.compliance)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn req_id ->
        # Convert from atom or underscore string to hyphenated string
        id_str =
          req_id
          |> to_string()
          |> String.replace("_", "-")

        %{
          "id" => id_str,
          "status" => "planned",
          "coverage" => 0
        }
      end)

    %{
      "total_requirements" => length(requirements),
      "covered_count" => 0,
      "planned_count" => length(requirements),
      "requirements" => requirements
    }
  end

  defp test_coverage_status do
    # TODO: Implement test coverage detection
    %{
      "unit" => 0,
      "integration" => 0,
      "e2e" => 0
    }
  end

  defp ci_status(project_root) do
    lock_current = match?(:ok, Foundry.Context.LockFile.check(project_root))

    base = %{
      "context_lock_current" => lock_current,
      "last_run_at" => nil,
      "commit" => nil,
      "branch" => nil,
      "lint_passed" => nil,
      "tests_passed" => nil
    }

    # Overlay with CI-written status file if present
    case Foundry.FileSystem.read(project_root, ".foundry/ci_status.json") do
      {:ok, content} ->
        Map.merge(base, Jason.decode!(content))

      _error ->
        base
    end
  end

  defp manifest_summary(manifest) do
    domain_type = Keyword.get(manifest, :domain_type, "")
    domain_type_str = if is_atom(domain_type), do: Atom.to_string(domain_type), else: domain_type

    %{
      "domain_type" => domain_type_str,
      "sensitive_resources" => Keyword.get(manifest, :sensitive_resources, [])
    }
  end
end
