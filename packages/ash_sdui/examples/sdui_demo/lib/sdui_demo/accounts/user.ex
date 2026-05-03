defmodule SduiDemo.Accounts.User do
  use Ash.Resource,
    domain: SduiDemo.Accounts,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(true)
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
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
