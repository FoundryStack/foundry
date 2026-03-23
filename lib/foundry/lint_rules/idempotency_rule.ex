defmodule Foundry.LintRules.IdempotencyRule do
  @behaviour SparkLint.Rule

  @side_effect_steps ~w[create update destroy action run step]

  def check(module, ctx) do
    info = Foundry.SparkMeta.walk(module)
    project_root = ctx.metadata[:project_root]

    cond do
      info.type not in [:transfer, :reactor] ->
        {:ok, []}

      not has_side_effects?(info.steps) ->
        {:ok, []}

      not has_idempotency_key?(module, project_root) ->
        {:ok, [%SparkLint.Violation{
          rule:     :missing_idempotency,
          module:   module,
          message:  "#{inspect module} has side effects but declares no @idempotency_key",
          severity: :error
        }]}

      true ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  defp has_side_effects?(steps) do
    Enum.any?(steps, &(&1.type in @side_effect_steps))
  end

  defp has_idempotency_key?(module, project_root) do
    attrs = module.__info__(:attributes)
    has_attr? = !is_nil(attrs[:idempotency_key]) or !is_nil(attrs[:idempotency])

    # Fallback: check source file for Reactor modules where attributes may not be preserved
    has_attr? || has_idempotency_in_source?(module, project_root)
  rescue
    _ -> false
  end

  defp has_idempotency_in_source?(module, project_root) do
    try do
      module_str = Atom.to_string(module)
      # Look for @idempotency_key or @idempotency in the source file
      case find_module_source_file(module_str, project_root) do
        nil -> false
        file -> idempotency_in_file?(file, module_str)
      end
    rescue
      _ -> false
    end
  end

  defp idempotency_in_file?(file, module_str) do
    try do
      # Strip "Elixir." prefix if present
      clean_module_str = String.replace_prefix(module_str, "Elixir.", "")

      content = File.read!(file)
      lines = String.split(content, "\n")

      # Find the module's defmodule line
      module_line_idx =
        lines
        |> Enum.find_index(fn line ->
          String.contains?(line, "defmodule #{clean_module_str}")
        end)

      case module_line_idx do
        nil ->
          false

        idx ->
          # Extract only the lines for this module's block (until the next defmodule)
          rest = Enum.drop(lines, idx + 1)

          module_lines =
            Enum.take_while(rest, fn line ->
              not String.match?(line, ~r/^\s*defmodule\s+\w/)
            end)

          # Check if @idempotency_key or @idempotency exists
          Enum.any?(module_lines, fn line ->
            String.contains?(line, "@idempotency_key") or
              String.contains?(line, "@idempotency")
          end)
      end
    rescue
      _ -> false
    end
  end

  # Search for the module's source file in lib/ directories
  defp find_module_source_file(module_str, project_root) do
    # Convert Module.Name to module/name.ex (with underscoring applied)
    # Module format: "Elixir.ProjectName.Section.Module"
    # File path: lib/section/module.ex (project name prefix is omitted)
    parts = String.split(module_str, ".")

    filename_lower =
      (parts
       |> Enum.drop(2)
       |> Enum.map(&Macro.underscore/1)
       |> Enum.join("/")) <> ".ex"

    # Try standard patterns first
    candidates = [
      Path.join(project_root, "lib/#{filename_lower}"),
      Path.join(project_root, filename_lower)
    ]

    case Enum.find(candidates, &File.exists?/1) do
      nil ->
        # Fallback: search lib recursively for the module definition (for multi-module files)
        search_lib_files(Path.join(project_root, "lib"), module_str)

      file ->
        file
    end
  end

  # Search .ex files in lib and subdirectories for module definition
  defp search_lib_files(lib_path, module_str) do
    try do
      # Strip "Elixir." prefix if present (Atom.to_string includes it)
      clean_module_str = String.replace_prefix(module_str, "Elixir.", "")

      lib_path
      |> File.ls!()
      |> Enum.find_value(fn entry ->
        full_path = Path.join(lib_path, entry)

        cond do
          File.dir?(full_path) ->
            # Recurse into subdirectory
            search_lib_files(full_path, module_str)

          String.ends_with?(entry, ".ex") ->
            case File.read(full_path) do
              {:ok, content} ->
                if String.contains?(content, "defmodule #{clean_module_str}") do
                  full_path
                else
                  nil
                end

              _ ->
                nil
            end

          true ->
            nil
        end
      end)
    rescue
      _ -> nil
    end
  end
end
