defmodule Foundry.Chat.ShellTools do
  @moduledoc """
  Shell tools for API-based LLM providers.
  Defines read_file, list_directory, and run_bash tools that can be used by Gemini and other API providers.

  ## Security

  The `run_bash` tool enforces a command allowlist by default to prevent LLM prompt injection.
  Allowlisted prefixes are safe for read-only and basic queries (git, mix, ls, grep, etc.).
  Configure `:shell_tools_policy` to `:open` to allow arbitrary commands (not recommended in production).
  """

  @safe_command_prefixes ~w(mix cat ls grep find git echo wc head tail sort uniq pwd which)

  @doc """
  Returns tool definitions as maps suitable for Gemini tool declarations.
  """
  def all do
    [read_file_schema(), list_directory_schema(), run_bash_schema()]
  end

  @doc """
  Executes a tool by name with the given arguments and project root.
  Returns {:ok, output} or {:error, reason}.
  """
  def execute(tool_name, arguments, project_root) when is_binary(tool_name) and is_map(arguments) do
    case tool_name do
      "read_file" -> execute_read_file(arguments, project_root)
      "list_directory" -> execute_list_directory(arguments, project_root)
      "run_bash" -> execute_run_bash(arguments, project_root)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end
  end

  defp read_file_schema do
    %{
      "name" => "read_file",
      "description" => "Read the contents of a file within the project",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Relative path to the file to read"
          }
        },
        "required" => ["path"]
      }
    }
  end

  defp list_directory_schema do
    %{
      "name" => "list_directory",
      "description" => "List the contents of a directory within the project",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Relative path to the directory to list (use '.' for project root)"
          }
        },
        "required" => ["path"]
      }
    }
  end

  defp run_bash_schema do
    %{
      "name" => "run_bash",
      "description" => "Run a bash command in the project root directory",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "string",
            "description" => "The bash command to execute"
          }
        },
        "required" => ["command"]
      }
    }
  end

  defp execute_read_file(%{"path" => path}, project_root) when is_binary(path) do
    case Foundry.FileSystem.read(project_root, path) do
      {:ok, content} -> {:ok, String.slice(content, 0, 8_000)}
      {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp execute_read_file(_, _) do
    {:error, "Missing required parameter: path"}
  end

  defp execute_list_directory(%{"path" => path}, project_root) when is_binary(path) do
    root = Path.expand(project_root)
    expanded = Path.expand(Path.join(root, path))

    if String.starts_with?(expanded, root <> "/") or expanded == root do
      case File.ls(expanded) do
        {:ok, entries} ->
          formatted = Enum.sort(entries) |> Enum.join("\n")
          {:ok, formatted}

        {:error, reason} ->
          {:error, "Failed to list directory: #{inspect(reason)}"}
      end
    else
      {:error, "Path outside project boundary"}
    end
  end

  defp execute_list_directory(_, _) do
    {:error, "Missing required parameter: path"}
  end

  defp execute_run_bash(%{"command" => command}, project_root) when is_binary(command) do
    case check_command_allowed?(command) do
      :ok -> do_execute_bash(command, project_root)
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_run_bash(_, _) do
    {:error, "Missing required parameter: command"}
  end

  defp check_command_allowed?(command) do
    case Application.get_env(:foundry, :shell_tools_policy, :allowlist) do
      :open ->
        :ok

      :allowlist ->
        if is_allowlisted_command?(command) do
          :ok
        else
          {:error, "Command not allowed by shell_tools_policy: allowlist. Use `:open` policy to allow arbitrary commands."}
        end
    end
  end

  defp is_allowlisted_command?(command) do
    trimmed = String.trim(command)

    safe? =
      Enum.any?(@safe_command_prefixes, fn prefix ->
        String.starts_with?(trimmed, prefix) and
          (String.length(trimmed) == String.length(prefix) or
             String.at(trimmed, String.length(prefix)) == " ")
      end)

    dangerous? = String.contains?(trimmed, ["&&", "||", ";", "$(", "`", "|"])

    safe? and not dangerous?
  end

  defp do_execute_bash(command, project_root) do
    timeout_ms = 30_000
    root = Path.expand(project_root)

    case MuonTrap.cmd("sh", ["-c", command], [
      {:cd, root},
      {:timeout, timeout_ms}
    ]) do
      {output, 0} ->
        truncated = String.slice(output, 0, 8_000)
        {:ok, truncated}

      {output, exit_code} ->
        truncated = String.slice(output, 0, 8_000)
        {:ok, "Exit code: #{exit_code}\n#{truncated}"}
    end
  rescue
    e ->
      {:error, "Command execution error: #{inspect(e)}"}
  end
end
