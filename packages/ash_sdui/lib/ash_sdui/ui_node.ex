defmodule AshSDUI.UINode do
  @moduledoc """
  Core Ash Resource representing a single node in the UI graph.

  Applications must configure the data layer via config:

      config :ash_sdui, AshSDUI.UINode,
        data_layer: AshPostgres.DataLayer

  Or by using this resource as a base and adding a data layer in their own resource.
  """

  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple,
    extensions: [AshPaperTrail.Resource],
    notifiers: [AshSDUI.Notifier]

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
  end

  attributes do
    uuid_primary_key :id

    attribute :component_name, :string do
      allow_nil? false
      constraints [
        match: ~r/^[A-Za-z0-9\.]+@v\d+$/
      ]
    end

    attribute :static_props, :map, default: %{}

    attribute :subject_resource, :string
    attribute :subject_id, :uuid

    attribute :region, :atom, default: :default
    attribute :order, :integer, default: 0

    attribute :status, :atom do
      allow_nil? false
      default :draft
      constraints one_of: [:draft, :published, :archived]
    end

    attribute :name, :string

    timestamps()
  end

  relationships do
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, destination_attribute: :parent_id
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :publish do
      change set_attribute(:status, :published)
    end

    update :revert do
      change set_attribute(:status, :archived)
    end
  end
end
