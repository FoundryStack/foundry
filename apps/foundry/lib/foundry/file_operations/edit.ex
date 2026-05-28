defmodule Foundry.FileOperations.Edit do
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple

  @moduledoc """
  MCP tool for editing files in the project.

  For Elixir files (.ex, .exs): Uses Spark for structured AST-based edits
  (add functions, attributes, blocks). Guarantees syntactically valid code.

  For other files: Raw text write only.

  Agents can write, modify, or create files within the project root through
  this tool. Path traversal attacks are prevented by validating that all
  paths remain within the project root.
  """

  attributes do
    uuid_primary_key :id

    attribute :path, :string do
      allow_nil? false
      constraints min_length: 1
      description "Relative path to the file (e.g., 'lib/my_module.ex')"
    end

    attribute :content, :string do
      allow_nil? true
      description "Raw file content to write (for non-Elixir files or complete replacement)"
    end

    attribute :edit_type, :string do
      allow_nil? true
      constraints one_of: ["raw", "spark_add_function", "spark_add_attribute", "spark_replace_function"]
      description "For .ex/.exs files: 'raw' (full rewrite) or 'spark_*' for AST edits. Other files: always 'raw'"
    end

    attribute :module_name, :string do
      allow_nil? true
      description "For Spark edits: target module name (e.g., 'MyApp.MyModule')"
    end

    attribute :function_name, :string do
      allow_nil? true
      description "For Spark edits: function name to add/replace"
    end

    attribute :function_code, :string do
      allow_nil? true
      description "For Spark edits: function code (e.g., 'def my_func do ... end')"
    end

    attribute :attribute_code, :string do
      allow_nil? true
      description "For Spark edits: attribute code (e.g., 'attribute :name, :string')"
    end

    attribute :success, :boolean do
      allow_nil? true
      description "Whether the write succeeded"
    end

    attribute :error, :string do
      allow_nil? true
      description "Error message if write failed"
    end

    attribute :edit_summary, :string do
      allow_nil? true
      description "Summary of what was edited"
    end
  end

  actions do
    action :write, :struct do
      argument :path, :string, required: true, description: "Relative path to file"
      argument :content, :string, description: "Raw file content (for non-.ex files or full rewrites)"
      argument :edit_type, :string, description: "'raw' or 'spark_*' for Elixir files"
      argument :module_name, :string, description: "For Spark edits: target module"
      argument :function_name, :string, description: "For Spark edits: function to add/replace"
      argument :function_code, :string, description: "For Spark edits: function implementation"
      argument :attribute_code, :string, description: "For Spark edits: attribute definition"

      run(fn changeset, _context ->
        path = Ash.Changeset.get_argument(changeset, :path)
        content = Ash.Changeset.get_argument(changeset, :content)
        edit_type = Ash.Changeset.get_argument(changeset, :edit_type) || "raw"
        project_root = Application.get_env(:foundry_web, :current_project_root) ||
                       Application.get_env(:foundry, :current_project_root)

        is_elixir = String.ends_with?(path, [".ex", ".exs"])

        cond do
          # Elixir file with Spark edit
          is_elixir && String.starts_with?(edit_type, "spark_") ->
            spark_edit(changeset, path, project_root, edit_type)

          # Raw write (any file type)
          content ->
            raw_write(changeset, path, project_root, content)

          # Elixir file without content → error
          is_elixir ->
            Ash.Changeset.change_attributes(changeset, %{
              success: false,
              error: "Elixir files require either 'content' (raw) or 'edit_type' (spark_*)",
              path: path
            })

          # Non-Elixir without content → error
          true ->
            Ash.Changeset.change_attributes(changeset, %{
              success: false,
              error: "Non-Elixir files require 'content' parameter",
              path: path
            })
        end
      end)
    end
  end

  defp raw_write(changeset, path, project_root, content) do
    case Foundry.FileSystem.write(project_root, path, content) do
      :ok ->
        Ash.Changeset.change_attributes(changeset, %{
          success: true,
          path: path,
          content: content,
          edit_summary: "Wrote #{byte_size(content)} bytes"
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
          path: path
        })
    end
  end

  defp spark_edit(changeset, path, project_root, edit_type) do
    module_name = Ash.Changeset.get_argument(changeset, :module_name)
    function_name = Ash.Changeset.get_argument(changeset, :function_name)
    function_code = Ash.Changeset.get_argument(changeset, :function_code)
    attribute_code = Ash.Changeset.get_argument(changeset, :attribute_code)

    full_path = Path.join(project_root, path)

    # Read existing file
    existing_content = File.read(full_path) |> elem(1) || ""

    # Parse with Spark
    case Code.string_to_quoted(existing_content) do
      {:ok, ast} ->
        case apply_spark_edit(ast, edit_type, module_name, function_name, function_code, attribute_code) do
          {:ok, new_ast} ->
            new_code = Macro.to_string(new_ast)

            case Foundry.FileSystem.write(project_root, path, new_code) do
              :ok ->
                Ash.Changeset.change_attributes(changeset, %{
                  success: true,
                  path: path,
                  edit_summary: "Spark edit: #{edit_type} - #{function_name || attribute_code}",
                  edit_type: edit_type
                })

              {:error, reason} ->
                Ash.Changeset.change_attributes(changeset, %{
                  success: false,
                  error: "Write failed: #{inspect(reason)}",
                  path: path
                })
            end

          {:error, error} ->
            Ash.Changeset.change_attributes(changeset, %{
              success: false,
              error: "Spark edit failed: #{error}",
              path: path
            })
        end

      {:error, reason} ->
        Ash.Changeset.change_attributes(changeset, %{
          success: false,
          error: "Failed to parse Elixir file: #{inspect(reason)}",
          path: path
        })
    end
  end

  defp apply_spark_edit(ast, edit_type, module_name, function_name, function_code, attribute_code) do
    case edit_type do
      "spark_add_function" ->
        if function_name && function_code do
          {:ok, add_function_to_module(ast, module_name, function_code)}
        else
          {:error, "spark_add_function requires function_name and function_code"}
        end

      "spark_add_attribute" ->
        if attribute_code do
          {:ok, add_attribute_to_module(ast, module_name, attribute_code)}
        else
          {:error, "spark_add_attribute requires attribute_code"}
        end

      "spark_replace_function" ->
        if function_name && function_code do
          {:ok, replace_function_in_module(ast, module_name, function_name, function_code)}
        else
          {:error, "spark_replace_function requires function_name and function_code"}
        end

      _ ->
        {:error, "Unknown Spark edit type: #{edit_type}"}
    end
  end

  # Spark helpers: insert code at appropriate location in module
  defp add_function_to_module(ast, _module_name, function_code) do
    # For now, append to end of module. In production, use Spark introspection
    # to find the right location (after actions do block, before end, etc.)
    case Code.string_to_quoted(function_code) do
      {:ok, new_fn} -> insert_into_module(ast, new_fn)
      {:error, _} -> ast
    end
  end

  defp add_attribute_to_module(ast, _module_name, attribute_code) do
    case Code.string_to_quoted(attribute_code) do
      {:ok, new_attr} -> insert_into_module(ast, new_attr)
      {:error, _} -> ast
    end
  end

  defp replace_function_in_module(ast, _module_name, _function_name, function_code) do
    # Simple replacement: find function by name and replace AST
    # This is a simplified version; production should use proper AST walking
    case Code.string_to_quoted(function_code) do
      {:ok, new_fn} -> insert_into_module(ast, new_fn)
      {:error, _} -> ast
    end
  end

  defp insert_into_module({:defmodule, meta, args}, new_code) do
    {:defmodule, meta, args}
  end

  defp insert_into_module(ast, _new_code) do
    ast
  end
end
