# API Key Channel Migration

## Overview
Migrated API key operations from the AuthChannel to a dedicated ApiKeyChannel on the authenticated UserSocket, following the server-side architecture changes.

## Changes Made

### 1. New ApiKeyClient (`internal/phoenix/apikey_client.go`)
- Created dedicated client for API key operations
- Connects to `api_keys:{user_id}` channel on authenticated socket
- Implements:
  - `GenerateAPIKey()` - Generate new API key with optional name
  - `ListAPIKeys()` - List all user's API keys
  - `RevokeAPIKey()` - Revoke specific API key by ID
- Handles channel events:
  - `api_key_generated`
  - `api_keys_listed`
  - `api_key_revoked`
  - `api_key_error`

### 2. Updated AuthClient
- Removed all API key operations
- Now only handles:
  - Login/logout
  - Authentication status
  - Token refresh

### 3. Model Updates
- Added `apiKeyClient` field
- Added `userID` field to store authenticated user ID
- User ID required for joining `api_keys:{user_id}` channel

### 4. Connection Flow Updates
- API key channel joins automatically after authentication
- Join sequence:
  1. Auth socket → auth:lobby → authenticate
  2. Switch to user socket with JWT/API key
  3. Join conversation, status, AND api_keys channels

### 5. Command Handler Updates
- API key commands now check authentication first
- Use ApiKeyClient instead of AuthClient
- Show error if not authenticated

### 6. Channel Architecture

**Auth Socket** (`/auth_socket`):
- `auth:lobby` - Login, logout, status, token refresh only

**User Socket** (`/socket`) - Requires authentication:
- `conversation:*` - Chat conversations
- `status:*` - AI work progress updates  
- `api_keys:{user_id}` - API key management (NEW)

## Usage

API key commands remain the same but now require authentication:

```
/apikey generate     - Generate new API key
/apikey list        - List all API keys
/apikey revoke <id> - Revoke API key by ID
```

If not authenticated, commands will show:
```
You must be authenticated to manage API keys
```

## Benefits

1. **Security**: API key operations require authenticated connection
2. **Separation**: Auth operations cleanly separated from API key management
3. **User Isolation**: Each user connects to their own api_keys channel
4. **Consistency**: Follows server's channel architecture

## Technical Notes

- API keys have optional `name` field for identification
- Channel topic includes user ID: `api_keys:123e4567-e89b-12d3-a456-426614174000`
- All API key operations happen over authenticated WebSocket connection
- No API key operations possible on auth socket