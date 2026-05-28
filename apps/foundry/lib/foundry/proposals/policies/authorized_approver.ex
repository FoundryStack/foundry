defmodule Foundry.Proposals.Policies.AuthorizedApprover do
  @moduledoc """
  Policy check: Approver must be a named approver in the manifest with the correct role
  for this proposal's change_class, and cannot be the same person as the requester.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "Approver must be a named approver in the manifest."

  @impl true
  def match?(record, %{actor: actor}, _runtime) when is_struct(record) and not is_nil(actor) do
    if actor == record.requester do
      false
    else
      project_root = Application.get_env(:foundry, :current_project_root, File.cwd!())

      case Foundry.Manifest.Parser.read(project_root) do
        {:ok, manifest} -> authorized_by_manifest?(actor, record.change_class, manifest)
        {:error, _} -> false
      end
    end
  end

  def match?(_subject, _context, _runtime), do: false

  defp authorized_by_manifest?(actor, change_class, manifest) do
    approvers = Keyword.get(manifest, :approvers, [])
    required_role = required_role(change_class)
    allowed = approvers_for_role(approvers, required_role, manifest)
    actor in allowed
  end

  defp required_role(:sensitive), do: :sensitive_lead
  defp required_role(:compliance), do: :compliance_officer
  defp required_role(:behavioral), do: :domain_lead
  defp required_role(:structural), do: :developer

  defp approvers_for_role(approvers, role, manifest) do
    delegate_key = :"#{role}_delegate"
    primary = List.wrap(get_approver(approvers, role))
    delegate = List.wrap(get_approver(approvers, delegate_key))

    extra =
      case role do
        :developer -> Keyword.get(manifest, :developer_approvers, [])
        _ -> []
      end

    (primary ++ delegate ++ extra)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp get_approver(approvers, key) when is_list(approvers), do: Keyword.get(approvers, key)
  defp get_approver(approvers, key) when is_map(approvers), do: Map.get(approvers, key)
end
