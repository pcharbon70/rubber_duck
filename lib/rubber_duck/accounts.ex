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

  @doc """
  Validates a plaintext API key by hashing it and checking against stored hashes.
  
  Returns {:ok, user} if valid and not expired, {:error, reason} otherwise.
  """
  def validate_api_key(plaintext_key) when is_binary(plaintext_key) do
    require Ash.Query
    
    # Hash the plaintext key
    key_hash = :crypto.hash(:sha256, plaintext_key)
    
    # Find the API key by its hash using a query
    query = 
      RubberDuck.Accounts.ApiKey
      |> Ash.Query.filter(api_key_hash == ^key_hash)
      |> Ash.Query.load([:valid, :user])
    
    case Ash.read_one(query, authorize?: false) do
      {:ok, nil} ->
        {:error, :invalid_api_key}
        
      {:ok, api_key} ->
        if api_key.valid do
          {:ok, api_key.user}
        else
          {:error, :expired_api_key}
        end
        
      error ->
        error
    end
  end
  
  def validate_api_key(_), do: {:error, :invalid_api_key}
end
