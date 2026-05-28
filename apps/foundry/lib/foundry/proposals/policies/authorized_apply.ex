defmodule Foundry.Proposals.Policies.AuthorizedApply do
  @moduledoc """
  Policy check: Only authorized approvers can apply a proposal.
  :structural proposals with auto_apply: true in the manifest are applied automatically.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "Only authorized approvers can apply a proposal."

  @impl true
  def match?(record, %{actor: actor}, _runtime) when is_struct(record) do
    project_root = Application.get_env(:foundry, :current_project_root, File.cwd!())

    case Foundry.Manifest.Parser.read(project_root) do
      {:ok, manifest} ->
        auto_apply?(record, manifest) or
          Foundry.Proposals.Policies.AuthorizedApprover.match?(record, %{actor: actor}, [])

      {:error, _} ->
        false
    end
  end

  def match?(_subject, _context, _runtime), do: false

  defp auto_apply?(%{change_class: :structural}, manifest) do
    Keyword.get(manifest, :auto_apply, false) == true
  end

  defp auto_apply?(_record, _manifest), do: false
end
