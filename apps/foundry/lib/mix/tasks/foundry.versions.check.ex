defmodule Mix.Tasks.Foundry.Versions.Check do
  @shortdoc "Emit current dependency versions as JSON (INV-006)"

  @moduledoc """
  Reads `mix.exs` in the current project directory and emits the version of
  every known Foundry-ecosystem dependency as a JSON object.

  The output is consumed in two ways:

  1. Prepended to every LLM prompt as the first item (INV-006 / ADR-010).
     Without it, the copilot cannot distinguish Ash 2.x from Ash 3.x and will
     hallucinate deprecated DSL syntax.

  2. Cached in ETS keyed on `{:versions, mix_exs_mtime}` (ADR-015 Tier 2).
     Re-run only when `mix.exs` changes.

  ## Usage

      mix foundry.versions.check
      mix foundry.versions.check --json

  Both forms emit JSON to stdout. The `--json` flag is accepted for consistency
  with the other `mix foundry.*` tasks but changes nothing — this task always
  emits JSON.

  ## Output shape

  Matches `Foundry.Versions.VersionManifest`. Every known library is present;
  libraries not found in `mix.lock` are `null`. The `elixir_version` and
  `otp_version` fields are always populated.

  ## Error behaviour

  Exits non-zero if `mix.exs` cannot be read or `mix.lock` is absent.
  Does not fail on unknown or absent libraries — they become `null`.
  """

  use Mix.Task

  @known_deps [
    # Core
    :ash,
    :ash_postgres,
    :spark,
    :phoenix,
    :phoenix_live_view,
    :igniter,
    :ecto_sql,
    :postgrex,
    # Ash extensions
    :ash_state_machine,
    :ash_oban,
    :ash_double_entry,
    :ash_json_api,
    :ash_paper_trail,
    :ash_archival,
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_money,
    # Money
    :ex_money,
    :ex_money_sql,
    # Jobs
    :oban,
    # Feature flags
    :fun_with_flags,
    # Rate limiting
    :hammer,
    :hammer_plug,
    # HTTP
    :req,
    :finch,
    :bandit,
    # Email
    :swoosh,
    # Caching
    :nebulex,
    # Clustering
    :libcluster,
    # Observability
    :opentelemetry,
    :opentelemetry_exporter,
    # Testing
    :stream_data,
    :bypass,
    :mox,
    :ex_machina,
    # UI
    :ash_pyro
  ]

  @impl Mix.Task
  def run(_args) do
    output = build_output(File.cwd!())
    IO.puts(output)
  end

  @doc """
  Build the versions JSON string for the given project root. Separated from
  `run/1` so tests can call this without triggering Mix.Sync.PubSub startup.
  Returns `{:ok, json_string}` or `{:error, reason}`.
  """
  def build_output(project_root) do
    versions_by_dep = read_lock!(project_root)

    versions =
      Map.new(@known_deps, fn dep ->
        {dep, Map.get(versions_by_dep, dep)}
      end)

    result =
      versions
      |> Map.put(:elixir_version, System.version())
      |> Map.put(:otp_version, otp_version())
      |> Map.put(:generated_at, DateTime.utc_now() |> DateTime.to_iso8601())

    Jason.encode!(result, pretty: true)
  end

  @doc "The list of known deps this task checks. Exposed for testing."
  def known_deps, do: @known_deps

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp read_lock!(project_root) do
    lock_path = Path.join(project_root, "mix.lock")

    unless File.exists?(lock_path) do
      Mix.raise("mix.lock not found at #{lock_path}. Run `mix deps.get` first.")
    end

    lock_path
    |> File.read!()
    |> Foundry.MixLock.versions_from_content(@known_deps)
  end

  defp otp_version do
    major = :erlang.system_info(:otp_release) |> List.to_string()

    minor_path =
      Path.join([:code.root_dir() |> List.to_string(), "releases", major, "OTP_VERSION"])

    case File.read(minor_path) do
      {:ok, vsn} -> String.trim(vsn)
      _ -> major
    end
  end
end
