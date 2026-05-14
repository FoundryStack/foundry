defmodule SduiDemo.Accounts do
  use Ash.Domain

  resources do
    resource SduiDemo.Accounts.User
  end
end
