defmodule RubberDuck.Accounts do
  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Accounts.Token
    resource RubberDuck.Accounts.User
    resource RubberDuck.Accounts.ApiKey
  end
end
