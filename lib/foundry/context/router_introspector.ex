defmodule Foundry.Context.RouterIntrospector do
  @moduledoc """
  Introspects Phoenix router modules to extract LiveView route metadata.

  Used by Foundry to discover page nodes from `Router.__routes__()` without
  requiring per-LiveView annotations. Extracts route path, module, and dynamic flag.
  """

  @doc """
  Extract all LiveView routes from a router module.

  Returns a list of maps with keys: `:module`, `:path`, `:dynamic`, `:helper`.
  """
  @spec liveview_routes(module()) :: [map()]
  def liveview_routes(router_module) do
    router_module.__routes__()
    |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
    |> Enum.map(fn route ->
      %{
        module: route.plug_opts,
        path: route.path,
        dynamic: String.contains?(route.path, ":"),
        helper: route.helper
      }
    end)
  rescue
    _ -> []
  end

  @doc """
  Find the router module for a given app by scanning for `__routes__/0`.

  Returns the module atom or nil if not found.
  """
  @spec find_router(atom()) :: module() | nil
  def find_router(app_name) do
    case Application.spec(app_name, :modules) do
      modules when is_list(modules) ->
        Enum.find(modules, fn mod ->
          try do
            function_exported?(mod, :__routes__, 0)
          rescue
            _ -> false
          end
        end)

      _ ->
        nil
    end
  end
end
