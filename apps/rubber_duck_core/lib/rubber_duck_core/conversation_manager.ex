defmodule RubberDuckCore.ConversationManager do
  @moduledoc """
  GenServer for managing conversations in the RubberDuck system.
  
  This server demonstrates the BaseServer pattern and provides
  conversation management functionality.
  """

  use RubberDuckCore.BaseServer

  alias RubberDuckCore.Conversation

  # Client API

  @doc """
  Creates a new conversation.
  """
  def create_conversation(server \\ __MODULE__, attrs \\ []) do
    GenServer.call(via_tuple(server), {:create_conversation, attrs})
  end

  @doc """
  Gets a conversation by ID.
  """
  def get_conversation(server \\ __MODULE__, conversation_id) do
    GenServer.call(via_tuple(server), {:get_conversation, conversation_id})
  end

  @doc """
  Adds a message to a conversation.
  """
  def add_message(server \\ __MODULE__, conversation_id, message) do
    GenServer.call(via_tuple(server), {:add_message, conversation_id, message})
  end

  @doc """
  Lists all conversations.
  """
  def list_conversations(server \\ __MODULE__) do
    GenServer.call(via_tuple(server), {:list_conversations})
  end

  # Server callbacks

  def initial_state(_args) do
    %{
      conversations: %{},
      conversation_count: 0
    }
  end

  def handle_call({:create_conversation, attrs}, _from, state) do
    conversation = Conversation.new(attrs)
    new_conversations = Map.put(state.conversations, conversation.id, conversation)
    
    new_state = %{state | 
      conversations: new_conversations,
      conversation_count: state.conversation_count + 1
    }
    
    {:reply, {:ok, conversation}, new_state}
  end

  def handle_call({:get_conversation, conversation_id}, _from, state) do
    case Map.get(state.conversations, conversation_id) do
      nil -> {:reply, {:error, :not_found}, state}
      conversation -> {:reply, {:ok, conversation}, state}
    end
  end

  def handle_call({:add_message, conversation_id, message}, _from, state) do
    case Map.get(state.conversations, conversation_id) do
      nil -> 
        {:reply, {:error, :conversation_not_found}, state}
      
      conversation ->
        updated_conversation = Conversation.add_message(conversation, message)
        new_conversations = Map.put(state.conversations, conversation_id, updated_conversation)
        new_state = %{state | conversations: new_conversations}
        
        {:reply, {:ok, updated_conversation}, new_state}
    end
  end

  def handle_call({:list_conversations}, _from, state) do
    conversations = Map.values(state.conversations)
    {:reply, {:ok, conversations}, state}
  end

  # Delegate unhandled calls to BaseServer
  def handle_call(msg, from, state) do
    super(msg, from, state)
  end
end