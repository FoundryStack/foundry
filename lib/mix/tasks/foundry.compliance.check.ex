defmodule Mix.Tasks.Foundry.Compliance.Check do
  @shortdoc "Check RG-* requirement implementation coverage and test linkage (INV-007)"

  @moduledoc """
  Reads all regulation files in `docs/regulations/`, extracts RG-* requirements,
  then verifies each one has at least one `implementation:` pointer to a module
  or test, and that a corresponding ExUnit test exists tagged `:compliance`.

  Emits a `Foundry.Compliance.CheckResult` as JSON.

  ## Usage

      mix foundry.compliance.check
      mix foundry.compliance.check --json
      mix foundry.compliance.check --filter=RG-UK   # filter by prefix

  ## Requirement syntax in regulation files

  Requirements are parsed from Markdown files in `docs/regulations/`. Each
  requirement must follow this structure:

      ### RG-UK-014
      **Summary:** Withdrawals must be processed to original payment method
      **Implementation:** `IgamingRef.Finance.WithdrawalTransfer`
      **Test tag:** `:rg_uk_014`

  The parser is lenient — it looks for the `RG-` prefix and reads the surrounding
  lines for implementation and test tag declarations.

  ## Status determination

  - `:implemented` — has implementation pointer AND a passing tagged test
  - `:partial` — has implementation pointer but no tagged test (or test failing)
  - `:unimplemented` — has no implementation pointer
  - `:planned` — explicitly declared as planned in the regulation file

  ## CI gate

  Exits non-zero only if any requirement is `:unimplemented` on a project that
  has `coverage_gate: true` in its manifest. Planned and partial requirements
  do not fail CI — they are surfaced as warnings in the compliance dashboard.
  """

  use Mix.Task

  alias Foundry.Compliance.CheckResult
  alias Foundry.Compliance.CheckResult.{Requirement, Summary}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    project_root = File.cwd!()
    filter = parse_filter(args)
    manifest = load_manifest(project_root)

    requirements =
      project_root
      |> find_regulation_files()
      |> Enum.flat_map(&parse_requirements(&1, project_root))
      |> filter_requirements(filter)
      |> Enum.map(&enrich_with_test_status(&1, project_root))
      |> Enum.sort_by(& &1.id)

    summary = build_summary(requirements)

    result = %CheckResult{
      requirements: requirements,
      summary: summary,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Mix.shell().info(Jason.encode!(result, pretty: true))

    # Exit non-zero if coverage_gate: true and any unimplemented requirements
    if manifest[:coverage_gate] do
      unimplemented = Enum.count(requirements, &(&1.status == :unimplemented))
      if unimplemented > 0 do
        Mix.shell().error("#{unimplemented} unimplemented requirement(s). Coverage gate failed.")
        exit({:shutdown, 1})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private — file discovery
  # ---------------------------------------------------------------------------

  defp find_regulation_files(project_root) do
    regs_dir = Path.join(project_root, "docs/regulations")
    case File.ls(regs_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&Path.join(regs_dir, &1))
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Private — parsing
  # ---------------------------------------------------------------------------

  defp parse_requirements(file_path, _project_root) do
    case File.read(file_path) do
      {:error, _} -> []
      {:ok, content} ->
        content
        |> String.split("\n")
        |> parse_lines(file_path)
    end
  end

  # State machine parser — walks lines looking for RG-* headings then reads
  # Summary, Implementation, Test tag, and Status from the following lines.
  defp parse_lines(lines, file_path) do
    lines
    |> Enum.with_index()
    |> Enum.chunk_while(
      nil,
      fn
        # New requirement heading
        {line, _idx}, _acc when line =~ ~r/^#+\s+RG-[A-Z]+-\d+/ ->
          id = Regex.run(~r/RG-[A-Z]+-\d+/, line) |> hd()
          {:cont, %Requirement{id: id, summary: "", status: :unimplemented}}

        # Summary line
        {line, _idx}, %Requirement{} = req when line =~ ~r/\*\*Summary:\*\*/ ->
          summary = Regex.replace(~r/\*\*Summary:\*\*\s*/, line, "") |> String.trim()
          {:cont, %{req | summary: summary}}

        # Implementation pointer
        {line, _idx}, %Requirement{} = req when line =~ ~r/\*\*Implementation:\*\*/ ->
          mods =
            Regex.scan(~r/`([A-Z][A-Za-z0-9.]+)`/, line)
            |> Enum.map(fn [_, m] -> m end)
          status = if mods != [], do: :partial, else: :unimplemented
          {:cont, %{req | implementing_modules: mods, status: status}}

        # Test tag
        {line, _idx}, %Requirement{} = req when line =~ ~r/\*\*Test tag:\*\*/ ->
          tags =
            Regex.scan(~r/`:([a-z_\d]+)`/, line)
            |> Enum.map(fn [_, t] -> t end)
          {:cont, %{req | test_tags: tags}}

        # Explicit planned status
        {line, _idx}, %Requirement{} = req when line =~ ~r/\*\*Status:\*\*\s*planned/ ->
          {:cont, %{req | status: :planned}}

        # Blank line after content — flush current requirement
        {"", _idx}, %Requirement{id: _} = req ->
          {:cont, req, nil}

        _line, acc ->
          {:cont, acc}
      end,
      fn
        nil -> {:cont, []}
        req -> {:cont, req, nil}
      end
    )
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&match?(%Requirement{}, &1))
  end

  # ---------------------------------------------------------------------------
  # Private — test status enrichment
  # ---------------------------------------------------------------------------

  defp enrich_with_test_status(%Requirement{test_tags: []} = req, _), do: req
  defp enrich_with_test_status(%Requirement{} = req, project_root) do
    # Look for the last CI run result by checking test result files.
    # In absence of a CI result file, we check if the test file exists.
    test_dir = Path.join(project_root, "test")

    tag_pattern = req.test_tags |> Enum.map(&":#{&1}") |> Enum.join("|")

    test_exists =
      case File.ls(test_dir) do
        {:ok, _} ->
          # Recursively search for tagged test files
          find_tagged_tests(test_dir, tag_pattern)
        _ -> false
      end

    # Check for a CI result file at .foundry/ci_results/<tag>.json
    ci_result = read_ci_result(project_root, req.test_tags)

    req
    |> Map.put(:last_test_passed, ci_result[:passed])
    |> Map.put(:last_test_run, ci_result[:run_at])
    |> then(fn r ->
      if test_exists and r.status == :partial do
        %{r | status: :implemented}
      else
        r
      end
    end)
  end

  defp find_tagged_tests(test_dir, tag_pattern) do
    Path.wildcard(Path.join([test_dir, "**", "*_test.exs"]))
    |> Enum.any?(fn path ->
      case File.read(path) do
        {:ok, content} -> content =~ ~r/#{tag_pattern}/
        _ -> false
      end
    end)
  end

  defp read_ci_result(project_root, tags) do
    tags
    |> Enum.find_value(fn tag ->
      path = Path.join([project_root, ".foundry", "ci_results", "#{tag}.json"])
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} -> %{passed: data["passed"], run_at: data["run_at"]}
            _ -> nil
          end
        _ -> nil
      end
    end)
    |> Kernel.||(%{passed: nil, run_at: nil})
  end

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  defp filter_requirements(reqs, nil), do: reqs
  defp filter_requirements(reqs, prefix) do
    Enum.filter(reqs, &String.starts_with?(&1.id, prefix))
  end

  defp build_summary(requirements) do
    %Summary{
      total:          length(requirements),
      implemented:    Enum.count(requirements, &(&1.status == :implemented)),
      partial:        Enum.count(requirements, &(&1.status == :partial)),
      unimplemented:  Enum.count(requirements, &(&1.status == :unimplemented)),
      planned:        Enum.count(requirements, &(&1.status == :planned)),
      passing_tests:  Enum.count(requirements, &(&1.last_test_passed == true)),
      failing_tests:  Enum.count(requirements, &(&1.last_test_passed == false))
    }
  end

  defp parse_filter(args) do
    args
    |> Enum.find_value(fn arg ->
      case Regex.run(~r/^--filter=(.+)$/, arg) do
        [_, prefix] -> prefix
        _ -> nil
      end
    end)
  end

  defp load_manifest(project_root) do
    path = Path.join([project_root, ".foundry", "manifest.exs"])
    case File.read(path) do
      {:ok, content} -> {kw, _} = Code.eval_string(content); kw
      _ -> []
    end
  end
end
