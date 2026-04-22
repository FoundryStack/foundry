defmodule SparkMeta.SourceProvider do
  @moduledoc """
  Source loading helpers for SparkMeta pipelines.
  """

  @type source_payload :: %{
          optional(:path) => String.t() | nil,
          optional(:text) => String.t() | nil,
          optional(:ast) => Macro.t() | nil
        }

  @type fetch_result :: {:ok, source_payload() | nil} | {:error, term()}

  @callback fetch(module()) :: fetch_result()

  defmodule FileSystem do
    @moduledoc """
    Default source provider that reads the module source file from compile metadata.
    """

    @behaviour SparkMeta.SourceProvider

    @impl SparkMeta.SourceProvider
    def fetch(module) when is_atom(module) do
      with path when is_binary(path) <- source_path(module),
           true <- File.exists?(path),
           {:ok, text} <- File.read(path) do
        {:ok,
         %{
           path: path,
           text: text,
           ast: parse_ast(text)
         }}
      else
        nil -> {:ok, nil}
        false -> {:ok, nil}
        {:error, reason} -> {:error, reason}
        _ -> {:ok, nil}
      end
    end

    defp source_path(module) do
      try do
        case module.__info__(:compile)[:source] do
          nil -> nil
          path when is_binary(path) -> path
          path -> to_string(path)
        end
      rescue
        _ -> nil
      end
    end

    defp parse_ast(text) do
      case Code.string_to_quoted(text) do
        {:ok, ast} -> ast
        _ -> nil
      end
    end
  end
end
