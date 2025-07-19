defmodule RubberDuckWeb.StatusChannel do
  @moduledoc """
  Channel for real-time status message delivery with category-based subscriptions.
  
  This channel enables clients to subscribe to status updates for specific conversations
  and categories. It integrates with the Status.Broadcaster system to deliver real-time
  updates via WebSocket connections.
  
  ## Joining the Channel
  
  Clients join with a conversation ID:
  ```
  channel.join("status:conversation123")
  ```
  
  ## Message Categories
  
  The following categories are supported:
  - `:engine` - Engine execution updates
  - `:tool` - Tool execution status
  - `:workflow` - Workflow progress updates
  - `:progress` - General progress indicators
  - `:error` - Error messages
  - `:info` - Informational messages
  
  ## Subscription Management
  
  After joining, clients can subscribe/unsubscribe to specific categories:
  
  ```javascript
  // Subscribe to categories
  channel.push("subscribe_categories", {categories: ["engine", "tool"]})
  
  // Unsubscribe from categories
  channel.push("unsubscribe_categories", {categories: ["error"]})
  
  // Get current subscriptions
  channel.push("get_subscriptions", {})
  ```
  
  ## Status Updates
  
  Status updates are pushed to clients as:
  ```
  {
    category: "engine",
    text: "Processing query...",
    metadata: {...},
    timestamp: "2024-01-19T12:00:00Z"
  }
  ```
  """
  
  use RubberDuckWeb, :channel
  require Logger
  
  alias RubberDuck.Conversations
  alias Phoenix.PubSub
  
  @allowed_categories ~w(engine tool workflow progress error info)a
  @max_categories_per_client 10
  @rate_limit_window_ms 60_000  # 1 minute
  @rate_limit_max_updates 30    # max subscription updates per window
  
  @impl true
  def join("status:" <> conversation_id, _params, socket) do
    Logger.info("User attempting to join status channel for conversation: #{conversation_id}")
    
    with {:ok, user_id} <- get_user_id(socket),
         :ok <- authorize_conversation_access(conversation_id, user_id) do
      
      # Initialize socket state
      socket = socket
        |> assign(:conversation_id, conversation_id)
        |> assign(:user_id, user_id)
        |> assign(:subscribed_categories, MapSet.new())
        |> assign(:rate_limit_counts, %{})
        |> assign(:joined_at, DateTime.utc_now())
      
      # Send welcome message with available categories
      send(self(), :after_join)
      
      {:ok, %{
        conversation_id: conversation_id,
        available_categories: @allowed_categories,
        subscribed_categories: []
      }, socket}
    else
      {:error, :unauthorized} ->
        Logger.warning("Unauthorized access attempt to conversation #{conversation_id}")
        {:error, %{reason: "unauthorized"}}
        
      {:error, reason} ->
        Logger.error("Failed to join status channel: #{inspect(reason)}")
        {:error, %{reason: "join_failed"}}
    end
  end
  
  @impl true
  def handle_info(:after_join, socket) do
    # Track presence
    {:ok, _} = RubberDuckWeb.Presence.track(
      socket,
      socket.assigns.user_id,
      %{
        online_at: DateTime.utc_now(),
        conversation_id: socket.assigns.conversation_id,
        subscribed_categories: MapSet.to_list(socket.assigns.subscribed_categories)
      }
    )
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:status_update, category, text, metadata}, socket) do
    # Only forward if client is subscribed to this category
    if MapSet.member?(socket.assigns.subscribed_categories, category) do
      push(socket, "status_update", %{
        category: to_string(category),
        text: text,
        metadata: metadata,
        timestamp: DateTime.utc_now()
      })
      
      # Emit telemetry event
      :telemetry.execute(
        [:rubber_duck, :status_channel, :message_delivered],
        %{count: 1},
        %{
          conversation_id: socket.assigns.conversation_id,
          category: category,
          user_id: socket.assigns.user_id
        }
      )
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("subscribe_categories", %{"categories" => categories}, socket) do
    with :ok <- check_rate_limit(socket, :subscribe),
         {:ok, valid_categories} <- validate_categories(categories),
         {:ok, new_socket} <- add_subscriptions(socket, valid_categories) do
      
      {:reply, {:ok, %{
        subscribed: MapSet.to_list(new_socket.assigns.subscribed_categories)
      }}, new_socket}
    else
      {:error, :rate_limited} ->
        {:reply, {:error, %{
          reason: "rate_limit_exceeded",
          message: "Too many subscription changes. Please try again later."
        }}, socket}
        
      {:error, {:invalid_categories, invalid}} ->
        {:reply, {:error, %{
          reason: "invalid_categories",
          invalid: invalid,
          valid: @allowed_categories
        }}, socket}
        
      {:error, :too_many_categories} ->
        {:reply, {:error, %{
          reason: "too_many_categories",
          message: "Maximum #{@max_categories_per_client} categories allowed",
          current_count: MapSet.size(socket.assigns.subscribed_categories)
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("unsubscribe_categories", %{"categories" => categories}, socket) do
    with :ok <- check_rate_limit(socket, :unsubscribe),
         {:ok, valid_categories} <- validate_categories(categories),
         {:ok, new_socket} <- remove_subscriptions(socket, valid_categories) do
      
      {:reply, {:ok, %{
        subscribed: MapSet.to_list(new_socket.assigns.subscribed_categories)
      }}, new_socket}
    else
      {:error, :rate_limited} ->
        {:reply, {:error, %{
          reason: "rate_limit_exceeded",
          message: "Too many subscription changes. Please try again later."
        }}, socket}
        
      {:error, {:invalid_categories, invalid}} ->
        {:reply, {:error, %{
          reason: "invalid_categories",
          invalid: invalid
        }}, socket}
    end
  end
  
  @impl true
  def handle_in("get_subscriptions", _params, socket) do
    {:reply, {:ok, %{
      subscribed_categories: MapSet.to_list(socket.assigns.subscribed_categories),
      available_categories: @allowed_categories
    }}, socket}
  end
  
  @impl true
  def terminate(reason, socket) do
    Logger.info("Status channel terminating for conversation #{socket.assigns.conversation_id}, reason: #{inspect(reason)}")
    
    # Unsubscribe from all PubSub topics
    Enum.each(socket.assigns.subscribed_categories, fn category ->
      topic = build_topic(socket.assigns.conversation_id, category)
      PubSub.unsubscribe(RubberDuck.PubSub, topic)
    end)
    
    # Emit telemetry for monitoring
    :telemetry.execute(
      [:rubber_duck, :status_channel, :disconnected],
      %{duration_ms: DateTime.diff(DateTime.utc_now(), socket.assigns.joined_at, :millisecond)},
      %{
        conversation_id: socket.assigns.conversation_id,
        user_id: socket.assigns.user_id,
        subscribed_categories: MapSet.to_list(socket.assigns.subscribed_categories)
      }
    )
    
    :ok
  end
  
  # Private functions
  
  defp get_user_id(socket) do
    case socket.assigns[:user_id] do
      nil -> {:error, :unauthorized}
      user_id -> {:ok, user_id}
    end
  end
  
  defp authorize_conversation_access(conversation_id, user_id) do
    case get_user_for_auth(user_id) do
      {:ok, user} ->
        case Conversations.get_conversation(conversation_id, actor: user) do
          {:ok, _conversation} -> :ok
          {:error, _} -> {:error, :unauthorized}
        end
        
      {:error, _} -> {:error, :unauthorized}
    end
  end
  
  defp get_user_for_auth(user_id) do
    RubberDuck.Accounts.get_user(user_id, authorize?: false)
  end
  
  defp validate_categories(categories) when is_list(categories) do
    categories = Enum.map(categories, &to_string/1)
    allowed_category_strings = Enum.map(@allowed_categories, &to_string/1)
    valid = Enum.filter(categories, fn cat -> cat in allowed_category_strings end)
    invalid = categories -- valid
    
    if Enum.empty?(invalid) do
      {:ok, Enum.map(valid, &String.to_existing_atom/1)}
    else
      {:error, {:invalid_categories, invalid}}
    end
  end
  defp validate_categories(_), do: {:error, {:invalid_categories, "categories must be a list"}}
  
  defp add_subscriptions(socket, categories) do
    current_categories = socket.assigns.subscribed_categories
    new_categories = MapSet.new(categories)
    combined = MapSet.union(current_categories, new_categories)
    
    if MapSet.size(combined) > @max_categories_per_client do
      {:error, :too_many_categories}
    else
      # Subscribe to new categories
      categories_to_add = MapSet.difference(new_categories, current_categories)
      
      Enum.each(categories_to_add, fn category ->
        topic = build_topic(socket.assigns.conversation_id, category)
        PubSub.subscribe(RubberDuck.PubSub, topic)
        
        Logger.debug("Subscribed to topic: #{topic}")
      end)
      
      # Update presence
      {:ok, _} = RubberDuckWeb.Presence.update(
        socket,
        socket.assigns.user_id,
        %{subscribed_categories: MapSet.to_list(combined)}
      )
      
      {:ok, assign(socket, :subscribed_categories, combined)}
    end
  end
  
  defp remove_subscriptions(socket, categories) do
    current_categories = socket.assigns.subscribed_categories
    categories_to_remove = MapSet.new(categories)
    remaining = MapSet.difference(current_categories, categories_to_remove)
    
    # Unsubscribe from removed categories
    Enum.each(categories_to_remove, fn category ->
      if MapSet.member?(current_categories, category) do
        topic = build_topic(socket.assigns.conversation_id, category)
        PubSub.unsubscribe(RubberDuck.PubSub, topic)
        
        Logger.debug("Unsubscribed from topic: #{topic}")
      end
    end)
    
    # Update presence
    {:ok, _} = RubberDuckWeb.Presence.update(
      socket,
      socket.assigns.user_id,
      %{subscribed_categories: MapSet.to_list(remaining)}
    )
    
    {:ok, assign(socket, :subscribed_categories, remaining)}
  end
  
  defp build_topic(conversation_id, category) do
    "status:#{conversation_id}:#{category}"
  end
  
  defp check_rate_limit(socket, _action) do
    current_time = System.monotonic_time(:millisecond)
    window_start = current_time - @rate_limit_window_ms
    
    # Clean old entries and count recent ones
    counts = socket.assigns.rate_limit_counts
    |> Enum.filter(fn {timestamp, _} -> timestamp > window_start end)
    |> Enum.into(%{})
    
    recent_count = counts
    |> Map.values()
    |> Enum.sum()
    
    if recent_count >= @rate_limit_max_updates do
      {:error, :rate_limited}
    else
      # Add new entry
      new_counts = Map.put(counts, current_time, 1)
      Process.put(:rate_limit_counts, new_counts)
      :ok
    end
  end
end