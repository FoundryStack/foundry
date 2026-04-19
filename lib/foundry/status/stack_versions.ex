defmodule Foundry.Status.StackVersions do
  @moduledoc """
  Extracts resolved stack dependency versions from mix.lock.
  """

  @tracked ~w[elixir ash ash_postgres phoenix reactor oban]a

  def read(project_root) do
    path = Path.join(project_root, "mix.lock")

    case File.read(path) do
      {:error, _} ->
        Map.new(@tracked, fn lib ->
          {to_string(lib), nil}
        end)

      {:ok, content} ->
        # Use regex to extract versions directly without evaluating the file.
        # This avoids thousands of "quoted keyword" warnings from Code.eval_string.
        Map.new(@tracked, fn lib ->
          pattern = ~r/"#{to_string(lib)}":\s*\{:hex,\s*:[^,]+,\s*"([^"]+)"/
          version =
            case Regex.run(pattern, content) do
              [_, v] -> v
              _ -> nil
            end
          {to_string(lib), version}
        end)
    end
  end

end
