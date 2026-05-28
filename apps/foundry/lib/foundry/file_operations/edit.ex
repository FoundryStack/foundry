defmodule Foundry.FileOperations.Edit do
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple

  @moduledoc """
  MCP tool for editing files in the project.

  Agents can write, modify, or create files within the project root
  through this tool. Path traversal attacks are prevented by validating
  that all paths remain within the project root.
  """

  attributes do
    uuid_primary_key :id

    attribute :path, :string do
      allow_nil? false
      constraints min_length: 1
      description "Relative path to the file (e.g., 'lib/my_module.ex')"
    end

    attribute :content, :string do
      allow_nil? false
      constraints min_length: 1
      description "File content to write"
    end

    attribute :success, :boolean do
      allow_nil? true
      description "Whether the write succeeded"
    end

    attribute :error, :string do
      allow_nil? true
      description "Error message if write failed"
    end
  end

  actions do
    action :write, :struct do
      argument :path, :string, required: true, description: "Relative path to file"
      argument :content, :string, required: true, description: "File content"

      run(fn changeset, _context ->
        path = Ash.Changeset.get_argument(changeset, :path)
        content = Ash.Changeset.get_argument(changeset, :content)
        project_root = Application.get_env(:foundry_web, :current_project_root) ||
                       Application.get_env(:foundry, :current_project_root)

        case Foundry.FileSystem.write(project_root, path, content) do
          :ok ->
            Ash.Changeset.change_attributes(changeset, %{
              success: true,
              path: path,
              content: content
            })

          {:error, reason} ->
            error_msg =
              case reason do
                :outside_boundary -> "Path is outside project root"
                reason -> inspect(reason)
              end

            Ash.Changeset.change_attributes(changeset, %{
              success: false,
              error: error_msg,
              path: path,
              content: content
            })
        end
      end)
    end
  end
end
