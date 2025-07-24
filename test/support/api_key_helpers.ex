defmodule RubberDuck.ApiKeyHelpers do
  @moduledoc """
  Helper functions for working with API keys in tests.
  
  Since AshAuthentication's GenerateApiKey only stores the hash,
  we need a different approach for testing. This module provides
  utilities to work around this limitation.
  """

  alias RubberDuck.Accounts.ApiKey

  @doc """
  Creates an API key for a user and returns a known plaintext value.
  
  Since we can't get the plaintext value from the normal creation process,
  we'll create our own API key and manually insert it.
  """
  def create_test_api_key(user, opts \\ []) do
    # Generate a test API key
    plaintext_key = opts[:key] || "rubberduck_test_" <> Base.encode64(:crypto.strong_rand_bytes(24), padding: false)
    
    # Hash the key the same way AshAuthentication does
    api_key_hash = :crypto.hash(:sha256, plaintext_key)
    
    expires_at = opts[:expires_at] || DateTime.utc_now() |> DateTime.add(365, :day)
    
    # Insert directly into the database using Ecto
    %ApiKey{}
    |> Ecto.Changeset.cast(%{
      user_id: user.id,
      api_key_hash: api_key_hash,
      expires_at: expires_at
    }, [:user_id, :api_key_hash, :expires_at])
    |> Ecto.Changeset.validate_required([:user_id, :api_key_hash, :expires_at])
    |> RubberDuck.Repo.insert()
    |> case do
      {:ok, api_key} ->
        # Load the valid calculation to ensure it's available
        {:ok, api_key} = Ash.load(api_key, [:valid], authorize?: false)
        {:ok, api_key, plaintext_key}
      error ->
        error
    end
  end
  
  @doc """
  Creates an expired API key for testing.
  """
  def create_expired_api_key(user, opts \\ []) do
    opts = Keyword.put(opts, :expires_at, DateTime.utc_now() |> DateTime.add(-1, :day))
    create_test_api_key(user, opts)
  end
end