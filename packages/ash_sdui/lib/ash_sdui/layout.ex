defmodule AshSDUI.Layout do
  @moduledoc """
  Simple registry for code-based UI layouts defined in Elixir.

  Layouts are registered at compile time by calling `register/2`.
  """

  @layout_key {__MODULE__, :layouts}

  defmodule Node do
    @moduledoc false
    defstruct [:id, :component, :bind_subject, :region, :order, :subject_resource, :subject_id, :children]
  end

  defmodule LayoutDef do
    @moduledoc false
    defstruct [:name, :root]
  end

  def register(name, layout_def) do
    current =
      case :persistent_term.get(@layout_key, nil) do
        nil -> %{}
        map -> map
      end

    :persistent_term.put(@layout_key, Map.put(current, name, layout_def))
  end

  def get(name) do
    map =
      case :persistent_term.get(@layout_key, nil) do
        nil -> %{}
        m -> m
      end

    case Map.get(map, name) do
      nil -> {:error, :not_found}
      layout -> {:ok, layout}
    end
  end

  def all do
    case :persistent_term.get(@layout_key, nil) do
      nil -> []
      map -> Map.values(map)
    end
  end
end
