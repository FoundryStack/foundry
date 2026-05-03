defmodule AshSDUI.Calculations.ResolveSubject do
  @moduledoc """
  Utility module for resolving {subject_resource, subject_id} into a live Ash record.
  """

  def resolve(record) do
    with resource_name when not is_nil(resource_name) <- record.subject_resource,
         subject_id when not is_nil(subject_id) <- record.subject_id,
         {:ok, resource_module} <- resolve_module(resource_name) do
      case Ash.get(resource_module, subject_id) do
        {:ok, result} -> result
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp resolve_module(resource_name) do
    module = Module.concat([resource_name])

    case Code.ensure_loaded(module) do
      {:module, mod} -> {:ok, mod}
      {:error, _} -> {:error, :not_loaded}
    end
  end
end
