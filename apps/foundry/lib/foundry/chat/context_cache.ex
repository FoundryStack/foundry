defmodule Foundry.Chat.ContextCache do
  @moduledoc """
  ETS-backed cache for expensive chat context assembly.

  The Studio copilot uses this to avoid rebuilding the full Foundry prompt and
  project graph on every turn when the relevant project inputs are unchanged.
  """

  @table :foundry_chat_context_cache
  @prompt_version 2

  alias Foundry.Context.ProjectContext

  @spec get_or_build(String.t()) :: {:ok, map()} | {:error, term()}
  def get_or_build(project_root) when is_binary(project_root) do
    ensure_table()

    project_root = Path.expand(project_root)
    fingerprint = fingerprint(project_root)
    key = {project_root, fingerprint, @prompt_version}

    case :ets.lookup(@table, key) do
      [{^key, payload}] ->
        {:ok, Map.put(payload, :cache, :hit)}

      [] ->
        with {:ok, payload} <- build_payload(project_root, fingerprint) do
          :ets.insert(@table, {key, payload})
          {:ok, Map.put(payload, :cache, :miss)}
        end
    end
  end

  @spec fingerprint(String.t()) :: String.t()
  def fingerprint(project_root) when is_binary(project_root) do
    inputs = [
      read_cache_input(project_root, ".foundry/context.lock"),
      read_cache_input(project_root, "AGENTS.md"),
      spec_kit_manifest(project_root)
    ]

    :sha256
    |> :crypto.hash(Enum.join(inputs, "\n--\n"))
    |> Base.encode16(case: :lower)
  end

  defp build_payload(project_root, fingerprint) do
    with {:ok, project_context} <- ProjectContext.build(project_root) do
      status = Foundry.Status.build(project_root)
      prompt = Foundry.Copilot.ContextBuilder.build(project_root: project_root)

      {:ok,
       %{
         project_root: project_root,
         fingerprint: fingerprint,
         prompt_version: @prompt_version,
         prompt: prompt,
         project_context: project_context,
         status: status,
         built_at: DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    end
  rescue
    error ->
      {:error, {:context_cache_build_failed, Exception.message(error)}}
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _tid ->
        :ok
    end
  end

  defp read_cache_input(project_root, relative_path) do
    case Foundry.FileSystem.read(project_root, relative_path) do
      {:ok, content} -> "#{relative_path}:#{content}"
      {:error, _reason} -> "#{relative_path}:missing"
    end
  end

  defp spec_kit_manifest(project_root) do
    [
      "docs/adrs/*.md",
      "docs/findings/*.md",
      "docs/runbooks/*.md",
      "docs/regulations/*.md",
      ".foundry/usage_rules/*.md"
    ]
    |> Enum.flat_map(&Path.wildcard(Path.join(project_root, &1)))
    |> Enum.sort()
    |> Enum.map(fn path ->
      rel = Path.relative_to(path, project_root)

      case File.stat(path) do
        {:ok, stat} ->
          "#{rel}:#{stat.size}:#{inspect(stat.mtime)}"

        {:error, _reason} ->
          "#{rel}:missing"
      end
    end)
    |> Enum.join("\n")
  end
end
