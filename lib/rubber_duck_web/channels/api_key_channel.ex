defmodule RubberDuckWeb.ApiKeyChannel do
  @moduledoc """
  Channel for managing API keys via WebSocket.

  This channel provides real-time API key management operations including
  generation, listing, and revocation. All operations require authentication
  through the UserSocket.

  ## Topics

  - `api_keys:manage` - Main topic for API key management

  ## Supported Operations

  - Generate new API keys with optional expiration
  - List all API keys for the authenticated user
  - Revoke specific API keys
  - Get API key statistics
  """

  use RubberDuckWeb, :channel
  require Logger

  alias RubberDuck.Accounts.ApiKey

  # Rate limiting configuration
  @max_api_key_generation_per_hour 10
  # @max_operations_per_minute 30

  @impl true
  def join("api_keys:manage", _params, socket) do
    # User is already authenticated via UserSocket
    user_id = socket.assigns.user_id
    Logger.info("User #{user_id} joined API key management channel")

    # Send initial statistics
    {:ok, get_api_key_stats(user_id), socket}
  end

  # Reject other api_keys topics
  def join("api_keys:" <> _other, _params, _socket) do
    {:error, %{reason: "unauthorized_topic"}}
  end

  @impl true
  def handle_in("generate", params, socket) do
    user_id = socket.assigns.user_id
    Logger.info("API key generation request from user #{user_id}")

    if check_generation_rate_limit(socket) do
      # Parse expiration time
      expires_at = parse_expiration(params["expires_at"])

      case generate_api_key_for_user(user_id, expires_at) do
        {:ok, api_key, key_value} ->
          push(socket, "api_key_generated", %{
            api_key: %{
              id: api_key.id,
              key: key_value,
              expires_at: DateTime.to_iso8601(api_key.expires_at),
              created_at: DateTime.to_iso8601(api_key.inserted_at)
            },
            warning: "Store this key securely - it won't be shown again"
          })

          Logger.info("API key generated for user #{user_id}: #{api_key.id}")

        {:error, reason} ->
          push(socket, "error", %{
            operation: "generate",
            message: "Failed to generate API key",
            details: format_error(reason)
          })
      end
    else
      push(socket, "error", %{
        operation: "generate",
        message: "Rate limit exceeded",
        details: "Too many API key generation attempts. Please try again later.",
        # seconds
        retry_after: 3600
      })

      Logger.warning("Rate limit exceeded for API key generation by user #{user_id}")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("generate_api_key", params, socket) do
    # Delegate to the existing generate handler
    handle_in("generate", params, socket)
  end

  @impl true
  def handle_in("list", params, socket) do
    user_id = socket.assigns.user_id

    # Support pagination
    page = params["page"] || 1
    per_page = params["per_page"] || 20

    case list_user_api_keys(user_id, page: page, per_page: per_page) do
      {:ok, %{results: api_keys} = page_info} ->
        formatted_keys =
          Enum.map(api_keys, fn key ->
            %{
              id: key.id,
              expires_at: DateTime.to_iso8601(key.expires_at),
              valid: key.valid,
              created_at: DateTime.to_iso8601(key.inserted_at)
            }
          end)

        push(socket, "api_key_list", %{
          api_keys: formatted_keys,
          page: page,
          per_page: per_page,
          # Get actual count if available
          total_count: page_info.count || length(formatted_keys)
        })

      {:error, reason} ->
        push(socket, "error", %{
          operation: "list",
          message: "Failed to list API keys",
          details: format_error(reason)
        })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("revoke", %{"api_key_id" => api_key_id}, socket) do
    user_id = socket.assigns.user_id

    case revoke_user_api_key(user_id, api_key_id) do
      :ok ->
        push(socket, "api_key_revoked", %{
          api_key_id: api_key_id,
          message: "API key revoked successfully"
        })

        Logger.info("API key #{api_key_id} revoked by user #{user_id}")

      {:error, reason} ->
        push(socket, "error", %{
          operation: "revoke",
          message: "Failed to revoke API key",
          details: format_error(reason)
        })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("get_stats", _params, socket) do
    user_id = socket.assigns.user_id
    stats = get_api_key_stats(user_id)

    push(socket, "stats", stats)

    {:noreply, socket}
  end

  @impl true
  def handle_in("validate", %{"api_key" => api_key}, socket) do
    case RubberDuck.Accounts.validate_api_key(api_key) do
      {:ok, user} ->
        push(socket, "api_key_valid", %{
          valid: true,
          user_id: user.id,
          username: user.username
        })

      {:error, :invalid_api_key} ->
        push(socket, "api_key_valid", %{
          valid: false,
          reason: "Invalid API key"
        })

      {:error, :expired_api_key} ->
        push(socket, "api_key_valid", %{
          valid: false,
          reason: "API key has expired"
        })

      {:error, _} ->
        push(socket, "error", %{
          operation: "validate",
          message: "Failed to validate API key"
        })
    end

    {:noreply, socket}
  end

  # Private helper functions

  defp generate_api_key_for_user(user_id, expires_at) do
    # Generate the plaintext API key first
    plaintext_key = "rubberduck_" <> Base.encode64(:crypto.strong_rand_bytes(32), padding: false)
    
    # Hash it the same way AshAuthentication does
    api_key_hash = :crypto.hash(:sha256, plaintext_key)
    
    # Get the user to use as actor
    actor = case RubberDuck.Accounts.get_user(user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
    
    # Create the API key directly with the hash
    # Note: We're bypassing the GenerateApiKey change because it doesn't expose the plaintext
    case Ash.create(ApiKey, %{
      user_id: user_id,
      expires_at: expires_at,
      api_key_hash: api_key_hash
    }, action: :create_with_hash, actor: actor) do
      {:ok, api_key} ->
        {:ok, api_key, plaintext_key}

      error ->
        error
    end
  end

  defp list_user_api_keys(user_id, opts) do
    require Ash.Query
    
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    # Get the user to use as actor
    actor = case RubberDuck.Accounts.get_user(user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end

    ApiKey
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:valid])
    |> Ash.Query.page(limit: per_page, offset: (page - 1) * per_page)
    |> Ash.read(actor: actor)
  end

  defp revoke_user_api_key(user_id, api_key_id) do
    require Ash.Query
    
    # Get the user to use as actor
    actor = case RubberDuck.Accounts.get_user(user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end

    # Build query to find the API key
    query = 
      ApiKey
      |> Ash.Query.filter(id == ^api_key_id and user_id == ^user_id)
      
    case Ash.read_one(query, actor: actor) do
      {:ok, nil} ->
        {:error, "API key not found or unauthorized"}
        
      {:ok, api_key} ->
        Ash.destroy(api_key, actor: actor)

      error ->
        error
    end
  end

  defp get_api_key_stats(_user_id) do
    # TODO: Implement actual statistics gathering
    # For now, return placeholder stats
    %{
      total_keys: 0,
      active_keys: 0,
      expired_keys: 0,
      revoked_keys: 0,
      generation_limit: %{
        used: 0,
        limit: @max_api_key_generation_per_hour,
        resets_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      }
    }
  end

  defp parse_expiration(nil), do: DateTime.utc_now() |> DateTime.add(365, :day)

  defp parse_expiration(expires_at) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now() |> DateTime.add(365, :day)
    end
  end

  defp parse_expiration(%DateTime{} = dt), do: dt
  defp parse_expiration(_), do: DateTime.utc_now() |> DateTime.add(365, :day)

  defp format_error(reason) do
    case reason do
      %Ash.Error.Invalid{errors: errors} ->
        errors
        |> Enum.map(fn error ->
          case error do
            %{message: message} -> message
            %Ash.Error.Invalid.NoSuchInput{input: input, resource: resource} ->
              "Invalid input '#{input}' for #{inspect(resource)}"
            _ -> inspect(error)
          end
        end)
        |> Enum.join(", ")

      %Ash.Error.Query.NotFound{} ->
        "Resource not found"

      binary when is_binary(binary) ->
        binary

      _ ->
        "An error occurred"
    end
  end

  # Rate limiting helpers
  # In production, replace with proper rate limiting like Hammer or similar

  defp check_generation_rate_limit(_socket) do
    # TODO: Implement proper rate limiting based on user/socket
    # For now, always return true (no rate limiting)
    true
  end
end
