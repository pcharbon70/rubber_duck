defmodule RubberDuck.Accounts do
  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Accounts.Token
    
    resource RubberDuck.Accounts.User do
      define :get_user, action: :read, get_by: [:id]
      define :list_users, action: :read
      define :authenticate_user, action: :sign_in_with_password
    end
    
    resource RubberDuck.Accounts.ApiKey do
      define :create_api_key, action: :create
      define :get_api_key, action: :read, get_by: [:id]
      define :list_api_keys, action: :read
      define :revoke_api_key, action: :destroy
      define :list_user_api_keys, action: :read
    end
  end
end
