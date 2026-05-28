defmodule Foundry.MCP.DocReader do
  @moduledoc """
  MCP resource wrapper for reading documentation files.

  Each action reads a specific documentation file and returns its full content as a string.
  Actions have `returns :string` so they can be exposed as MCP resources.
  """

  use Ash.Resource,
    domain: Foundry.Context,
    data_layer: Ash.DataLayer.Simple

  attributes do
    attribute :id, :string do
      primary_key?(true)
      allow_nil?(false)
    end
  end

  actions do
    action :agents_guide, :string do
      description("AGENTS.md — Agent specifications and integration patterns")

      run fn _input, _context ->
        project_root = File.cwd!()

        case Foundry.FileSystem.read(project_root, "AGENTS.md") do
          {:ok, content} -> {:ok, content}
          {:error, _} -> {:ok, ""}
        end
      end
    end

    action :adr_index_json, :string do
      description("Architecture Decision Records index — JSON catalog of all ADRs")

      run fn _input, _context ->
        project_root = File.cwd!()

        case Foundry.Context.SpecKitIndexBuilder.build(project_root) do
          %{"adrs" => adrs} when is_list(adrs) ->
            {:ok, Jason.encode!(adrs)}

          _ ->
            {:ok, "[]"}
        end
      end
    end

    action :runbooks_index_json, :string do
      description("Runbooks index — JSON catalog of operational runbooks for troubleshooting")

      run fn _input, _context ->
        project_root = File.cwd!()

        case Foundry.Context.SpecKitIndexBuilder.build(project_root) do
          %{"runbooks" => runbooks} when is_list(runbooks) ->
            {:ok, Jason.encode!(runbooks)}

          _ ->
            {:ok, "[]"}
        end
      end
    end

    action :build_sequence, :string do
      description("BUILD_SEQUENCE.md — How Foundry's build process works")

      run fn _input, _context ->
        project_root = File.cwd!()

        case Foundry.FileSystem.read(project_root, "docs/BUILD_SEQUENCE.md") do
          {:ok, content} -> {:ok, content}
          {:error, _} -> {:ok, ""}
        end
      end
    end

    action :implementation_summary, :string do
      description("IMPLEMENTATION_SUMMARY.md — Current system architecture and components")

      run fn _input, _context ->
        project_root = File.cwd!()

        case Foundry.FileSystem.read(project_root, "docs/IMPLEMENTATION_SUMMARY.md") do
          {:ok, content} -> {:ok, content}
          {:error, _} -> {:ok, ""}
        end
      end
    end

    action :lint_catalogue, :string do
      description("lint-catalogue.md — Complete catalog of lint rules and checks available")

      run fn _input, _context ->
        project_root = File.cwd!()

        case Foundry.FileSystem.read(project_root, "docs/lint-catalogue.md") do
          {:ok, content} -> {:ok, content}
          {:error, _} -> {:ok, ""}
        end
      end
    end
  end
end
