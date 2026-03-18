defmodule Foundry.Manifest.Reader do
  @moduledoc """
  Loads and validates the project manifest from `.foundry/manifest.exs`.
  Returns a validated Foundry.Manifest record or raises on error.
  """
  def load!(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        {kw, _} = Code.eval_string(content)
        load_from_kw!(kw)

      {:error, reason} ->
        raise "Cannot read manifest at #{path}: #{inspect(reason)}"
    end
  end

  def load_from_kw!(kw) when is_list(kw) do
    Ash.Changeset.for_create(Foundry.Manifest, :load, kw)
    |> Ash.Changeset.apply_action(:create)
    |> case do
      {:ok, record} ->
        record

      {:error, %Ash.Changeset{errors: errors}} ->
        raise "Manifest validation failed: #{inspect(errors)}"
    end
  end
end
