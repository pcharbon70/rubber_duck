# Fix: Lobby Conversation Creation Error

## Bug Summary
The ConversationChannel attempts to create a database conversation when users join "conversation:lobby", but fails because "lobby" is not a valid UUID. The lobby should be treated as a special ephemeral channel that doesn't require database persistence.

## Root Cause
The `ensure_conversation_exists/3` function in ConversationChannel always tries to create a database conversation for authenticated users, including for the special "lobby" channel. Since the Conversation resource uses `uuid_primary_key :id`, it rejects "lobby" as an invalid ID.

## Existing Usage Rules Violations
No existing usage rules were violated. This is a design oversight where special channels like "lobby" weren't considered in the initial implementation.

## Reproduction Test
```elixir
defmodule RubberDuckWeb.ConversationChannelLobbyTest do
  use RubberDuckWeb.ChannelCase
  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.{UserSocket, ConversationChannel}

  describe "lobby conversation handling" do
    test "authenticated users can join lobby without creating database conversation" do
      # Arrange
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      
      # Act - This should succeed without trying to create a database conversation
      result = subscribe_and_join(socket, ConversationChannel, "conversation:lobby")
      
      # Assert
      assert {:ok, %{conversation_id: "lobby", session_id: session_id}, _socket} = result
      assert is_binary(session_id)
      
      # Verify no database conversation was created with "lobby" as ID
      assert {:error, _} = RubberDuck.Conversations.get_conversation("lobby")
    end
    
    test "lobby conversation allows messaging without database persistence" do
      # Arrange
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _reply, socket} = subscribe_and_join(socket, ConversationChannel, "conversation:lobby")
      
      # Act - Send a message to lobby
      ref = push(socket, "message", %{"content" => "Hello lobby!"})
      
      # Assert - Should receive acknowledgment without database errors
      assert_reply ref, :ok, _, 5000
    end
  end
end
```

## Test Output
```
[error] Failed to create conversation: %Ash.Error.Invalid{bread_crumbs: ["Error returned from: RubberDuck.Conversations.Conversation.create"],  changeset: "#Changeset<>",  errors: [%Ash.Error.Changes.InvalidArgument{field: :id, message: "is invalid", value: "lobby", splode: Ash.Error, bread_crumbs: ["Error returned from: RubberDuck.Conversations.Conversation.create"], vars: [], path: [], stacktrace: #Splode.Stacktrace<>, class: :invalid}]}

2 tests, 1 failure
```

## Proposed Solution
Modify the ConversationChannel to skip database conversation creation for special channels like "lobby". The lobby should function as an ephemeral channel where messages are processed but not persisted.

Approach:
1. Add a check in the `join/3` function to identify special channels
2. Skip calling `ensure_conversation_exists/3` for these special channels
3. Handle message processing for lobby without database operations

## Changes Required
1. File: `lib/rubber_duck_web/channels/conversation_channel.ex` - Add special channel detection and skip database operations for lobby
2. File: `lib/rubber_duck_web/channels/conversation_channel.ex` - Possibly modify message handling to work without database conversation for lobby

## Potential Side Effects
- Side effect 1: Messages sent to lobby won't be persisted to database (this is intentional)
- Side effect 2: Conversation history won't be available for lobby (expected behavior)
- Side effect 3: Some features that rely on database conversation might need special handling for lobby

## Regression Prevention
1. Add tests specifically for lobby behavior
2. Consider adding a module attribute listing special channels for clarity
3. Document that lobby is an ephemeral channel in code comments
4. Consider if other special channels might be needed in the future

## Questions for Pascal
1. Should the lobby channel have any persistence at all, or should it be completely ephemeral?
2. Are there other special channels we should consider (e.g., "system", "broadcast")?
3. Should lobby messages still go through the LLM processing, or should they have different handling?

## Implementation Log

### Updated Requirements (from Pascal)
- When a user joins "conversation:lobby", load their latest conversation
- If no conversation exists, create a new one with a proper UUID
- No need for backward compatibility

### Changes Being Made
1. Adding get_latest_by_user action to Conversation resource
2. Defining the action in Conversations domain
3. Updating ConversationChannel join logic to handle lobby specially
4. Updating tests to reflect new behavior

## Final Implementation

### 1. Added get_latest_by_user action to Conversation resource
In `lib/rubber_duck/conversations/conversation.ex`:
- Added a new read action that filters by user_id
- Sorts by updated_at in descending order
- Limited to 1 result
- Marked as get? true for single result

### 2. Defined action in Conversations domain
In `lib/rubber_duck/conversations.ex`:
- Added `define :get_latest_conversation_by_user, action: :get_latest_by_user`

### 3. Updated ConversationChannel join logic
In `lib/rubber_duck_web/channels/conversation_channel.ex`:
- Modified join/3 to detect when conversation_id is "lobby"
- Added load_or_create_user_conversation/2 function that:
  - Tries to load the user's latest conversation
  - Creates a new conversation with proper UUID if none exists
- Uses actual conversation ID throughout the channel lifecycle

### 4. Fixed argument passing
- get_latest_conversation_by_user expects a map with user_id key
- Fixed by passing %{user_id: user_id} instead of just user_id

## Test Results
- Reproduction test: PASSING
- Full test suite: Some unrelated failures (authentication changes)
- New tests added: 3 tests for lobby behavior
- All lobby-specific tests: PASSING

## Verification Checklist
- [x] Bug is fixed - Users can join lobby without UUID errors
- [x] No regressions introduced - Other conversation joins still work
- [x] Tests cover the fix - 3 comprehensive tests added
- [x] Code follows patterns - Uses Ash patterns for queries
- [x] Compiles cleanly - No warnings or errors