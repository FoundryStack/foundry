defmodule Foundry.SparkMeta.Helpers do
  @moduledoc false

  def format_module_fqn(nil), do: nil

  def format_module_fqn(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  def format_module_fqn(module) when is_binary(module), do: module
  def format_module_fqn(_module), do: nil

  def get_attr_list(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> []
      list when is_list(list) -> Enum.map(list, &to_string/1)
      value -> [to_string(value)]
    end
  rescue
    _ -> []
  end

  def get_attr_raw(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> nil
      [value | _] -> value
      value -> value
    end
  rescue
    _ -> nil
  end

  def get_attr_single(attrs, key) do
    case Keyword.get(attrs, key) do
      nil -> nil
      [value | _] -> to_string(value)
      value -> to_string(value)
    end
  rescue
    _ -> nil
  end

  def module_source_path(module) when is_atom(module) do
    try do
      case module.__info__(:compile)[:source] do
        nil -> find_module_source_file(Atom.to_string(module))
        charlist ->
          path = to_string(charlist)
          if File.exists?(path), do: path, else: find_module_source_file(Atom.to_string(module))
      end
    rescue
      _ -> find_module_source_file(Atom.to_string(module))
    end
  end

  def find_module_source_file(module_str) do
    parts = String.split(module_str, ".")

    filename_lower =
      (parts
       |> Enum.drop(2)
       |> Enum.map(&Macro.underscore/1)
       |> Enum.join("/")) <> ".ex"

    cwd = File.cwd!()

    candidates = [
      Path.join(cwd, "lib/#{filename_lower}"),
      Path.join(cwd, filename_lower)
    ]

    case Enum.find(candidates, &File.exists?/1) do
      nil -> search_lib_files(Path.join(cwd, "lib"), module_str)
      file -> file
    end
  end

  def search_lib_files(lib_path, module_str) do
    try do
      clean_module_str = String.replace_prefix(module_str, "Elixir.", "")

      lib_path
      |> File.ls!()
      |> Enum.find_value(fn entry ->
        full_path = Path.join(lib_path, entry)

        cond do
          File.dir?(full_path) ->
            search_lib_files(full_path, module_str)

          String.ends_with?(entry, ".ex") ->
            case File.read(full_path) do
              {:ok, content} ->
                if String.contains?(content, "defmodule #{clean_module_str}"), do: full_path, else: nil

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

  def extract_runbook_from_source(module) do
    try do
      module_str = Atom.to_string(module)

      case module_source_path(module) do
        nil -> nil
        file -> extract_runbook_from_file(file, module_str)
      end
    rescue
      _ -> nil
    end
  end

  def extract_runbook_from_file(file, module_str) do
    try do
      clean_module_str = String.replace_prefix(module_str, "Elixir.", "")
      content = File.read!(file)
      lines = String.split(content, "\n")

      module_line_idx =
        Enum.find_index(lines, fn line ->
          String.contains?(line, "defmodule #{clean_module_str}")
        end)

      case module_line_idx do
        nil ->
          nil

        idx ->
          lines
          |> Enum.drop(idx + 1)
          |> Enum.take_while(&(not String.match?(&1, ~r/^\s*defmodule\s+\w/)))
          |> Enum.find_value(fn line ->
            case Regex.run(~r/@runbook\s+"([^"]+)"/, line) do
              [_, path] -> path
              _ -> nil
            end
          end)
      end
    rescue
      _ -> nil
    end
  end
end
