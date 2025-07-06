defmodule RubberDuck.Memory.Interaction do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Memory,
    data_layer: Ash.DataLayer.Ets
  
  require Ash.Query

  @moduledoc """
  Short-term memory storage for user interactions.
  Uses ETS for fast in-memory access with FIFO eviction after 20 interactions per session.
  """

  ets do
    table :memory_interactions
    private? false  # Allow access across processes
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :string do
      allow_nil? false
      public? true
    end

    attribute :session_id, :string do
      allow_nil? false
      public? true
    end

    attribute :type, :atom do
      allow_nil? false
      constraints one_of: [:chat, :question, :code_generation, :code_completion, :error]
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :metadata, :map do
      allow_nil? true
      default %{}
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      default 0
      public? true
    end

    create_timestamp :inserted_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :session_id, :type, :content, :metadata]
      
      # Implement FIFO logic
      change fn changeset, _context ->
        user_id = Ash.Changeset.get_attribute(changeset, :user_id)
        session_id = Ash.Changeset.get_attribute(changeset, :session_id)
        
        # Count existing interactions for this session
        case count_session_interactions(user_id, session_id) do
          {:ok, count} when count >= 20 ->
            # Remove oldest interaction
            remove_oldest_interaction(user_id, session_id)
            # Get the highest position and increment it
            highest_position = get_highest_position(user_id, session_id)
            Ash.Changeset.change_attribute(changeset, :position, highest_position + 1)
            
          {:ok, count} ->
            Ash.Changeset.change_attribute(changeset, :position, count + 1)
            
          _ ->
            changeset
        end
      end
    end

    read :by_session do
      argument :user_id, :string, allow_nil?: false
      argument :session_id, :string, allow_nil?: false
      
      filter expr(user_id == ^arg(:user_id) and session_id == ^arg(:session_id))
      prepare build(sort: [position: :desc])
    end
    
    read :by_user do
      argument :user_id, :string, allow_nil?: false
      
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  # Private helper functions
  defp count_session_interactions(user_id, session_id) do
    __MODULE__
    |> Ash.Query.for_read(:by_session, %{user_id: user_id, session_id: session_id})
    |> Ash.count(authorize?: false)
  end

  defp remove_oldest_interaction(user_id, session_id) do
    __MODULE__
    |> Ash.Query.for_read(:by_session, %{user_id: user_id, session_id: session_id})
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> case do
      [oldest | _] -> Ash.destroy!(oldest, authorize?: false)
      _ -> :ok
    end
  end
  
  defp get_highest_position(user_id, session_id) do
    __MODULE__
    |> Ash.Query.for_read(:by_session, %{user_id: user_id, session_id: session_id})
    |> Ash.Query.sort(position: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> case do
      [highest | _] -> highest.position
      _ -> 0
    end
  end
end