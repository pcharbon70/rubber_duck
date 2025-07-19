defmodule RubberDuck.Accounts do
  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Accounts.Token
    
    resource RubberDuck.Accounts.User do
      define :get_user, action: :read, get_by: [:id]
      define :list_users, action: :read
    end
    
    resource RubberDuck.Accounts.ApiKey
  end
end
