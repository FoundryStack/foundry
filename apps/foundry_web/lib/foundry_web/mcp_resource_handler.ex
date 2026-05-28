defmodule FoundryWeb.McpResourceHandler do
  @doc """
  Handle MCP resource requests (resources/list, resources/read, resources/templates).

  Exposes project files and modules as browsable MCP resources.
  """

  def handle_message(
        %{
          "method" => "resources/list",
          "params" => _params
        },
        _opts
      ) do
    resources = list_project_resources()

    %{
      "resources" => resources
    }
  end

  def handle_message(
        %{
          "method" => "resources/read",
          "params" => %{"uri" => uri}
        },
        _opts
      ) do
    case read_resource(uri) do
      {:ok, content} ->
        %{
          "contents" => [
            %{
              "uri" => uri,
              "mimeType" => mime_type(uri),
              "text" => content
            }
          ]
        }

      :error ->
        %{"error" => "not_found"}
    end
  end

  def handle_message(
        %{
          "method" => "resources/templates",
          "params" => _params
        },
        _opts
      ) do
    %{
      "resourceTemplates" => [
        %{
          "name" => "project",
          "description" => "Project root directory",
          "mimeType" => "text/directory",
          "uriTemplate" => "file:///{path}"
        },
        %{
          "name" => "module",
          "description" => "Elixir module file",
          "mimeType" => "text/x-elixir",
          "uriTemplate" => "file:///{path}.ex"
        }
      ]
    }
  end

  def handle_message(message, _opts) do
    nil
  end

  defp list_project_resources do
    root = Application.get_env(:foundry_web, :current_project_root) ||
           Application.get_env(:foundry, :current_project_root)

    require Logger
    Logger.info("MCP resources/list - project_root: #{inspect(root)}")

    if root && File.exists?(root) do
      root
      |> Path.expand()
      |> list_files_recursive(root, 0, 50)
      |> Enum.map(fn path ->
        uri = "file://" <> path

        %{
          "uri" => uri,
          "name" => Path.basename(path),
          "description" => "Project file",
          "mimeType" => mime_type(path)
        }
      end)
    else
      []
    end
  end

  defp list_files_recursive(_path, _root, depth, _max_depth) when depth > 10, do: []

  defp list_files_recursive(path, root, depth, max_depth) when depth < max_depth do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.flat_map(fn file ->
          full_path = Path.join(path, file)

          if File.dir?(full_path) do
            list_files_recursive(full_path, root, depth + 1, max_depth)
          else
            [full_path]
          end
        end)
        |> Enum.take(100)

      :error ->
        []
    end
  end

  defp read_resource(uri) do
    case URI.parse(uri) do
      %{scheme: "file", path: path} ->
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp mime_type(path) do
    case Path.extname(path) do
      ".ex" -> "text/x-elixir"
      ".exs" -> "text/x-elixir"
      ".eex" -> "text/x-elixir"
      ".json" -> "application/json"
      ".yaml" -> "text/yaml"
      ".yml" -> "text/yaml"
      ".md" -> "text/markdown"
      ".txt" -> "text/plain"
      _ -> "text/plain"
    end
  end
end
