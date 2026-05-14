defmodule SduiDemo.Accounts.User do
  use Ash.Resource,
    domain: SduiDemo.Accounts,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key :id

    attribute :username, :string do
      allow_nil? false
    end

    attribute :avatar_url, :string
    attribute :email, :string
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:username, :email, :avatar_url]
    end

    update :update do
      accept [:username, :email, :avatar_url]
    end
  end
end
