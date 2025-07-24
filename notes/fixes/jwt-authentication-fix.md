# JWT Authentication Fix

## Issue
After the authentication refactor (moving API key auth to AuthChannel), clients connecting to ConversationChannel were getting errors:
1. "Could not find user user?id=e9d33e45-d9bf-4032-8a36-87f4b8f89af8"
2. SessionContext process not found

## Root Causes
1. JWT subject format from AshAuthentication is `"user?id=UUID"` not just the UUID
2. SessionContext GenServer was not started in the application supervisor
3. ConversationChannel was using invalid `input:` option when creating conversations

## Fixes Applied

### 1. UserSocket JWT Subject Extraction
Added `extract_user_id_from_subject/1` function to properly extract the UUID from the JWT subject format:
```elixir
defp extract_user_id_from_subject(subject) when is_binary(subject) do
  case String.split(subject, "id=") do
    [_, user_id] -> user_id
    _ -> subject  # Fallback
  end
end
```

### 2. Started SessionContext in Application
Added `RubberDuck.SessionContext` to the application supervisor children list.

### 3. Fixed ConversationChannel 
Removed invalid `input:` option and set the ID in attributes directly:
```elixir
attrs = Map.put(attrs, :id, conversation_id)
case Conversations.create_conversation(attrs, actor: user) do
```

### 4. Updated Tests
- Updated UserSocket tests to use real JWT tokens from AshAuthentication
- Removed API key tests (moved to AuthSocket)
- Added JWT-specific tests

## Result
All authentication now flows correctly:
1. Client authenticates with AuthChannel (username/password or API key)
2. Receives JWT token
3. Connects to UserSocket with JWT
4. Can join ConversationChannel successfully