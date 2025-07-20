# API Key Management Channel

## Overview
Moved API key management functionality from AuthChannel to a dedicated ApiKeyChannel that uses the authenticated UserSocket. This provides better separation of concerns and ensures API key operations are only available to authenticated users.

## Implementation Date
January 20, 2025

## Changes Made

### 1. Created ApiKeyChannel (`lib/rubber_duck_web/channels/api_key_channel.ex`)
- Dedicated channel for API key management operations
- Requires authentication through UserSocket
- Topic: `api_keys:manage`

### 2. Channel Operations
- **Generate**: Create new API keys with optional expiration and name
- **List**: Retrieve user's API keys with pagination support
- **Revoke**: Delete specific API keys
- **Get Stats**: Retrieve API key usage statistics

### 3. Enhanced Features
- Broadcasting updates to other connected clients
- Rate limiting support (placeholder for future implementation)
- Pagination for listing API keys
- Custom key names and expiration dates
- Real-time statistics including generation limits

### 4. Removed from AuthChannel
- Removed all API key operations (generate, list, revoke)
- Removed helper functions for API key management
- Updated module documentation to reflect the change

### 5. Updated UserSocket
- Added `channel("api_keys:*", RubberDuckWeb.ApiKeyChannel)` registration

### 6. Comprehensive Test Suite
- Created `test/rubber_duck_web/channels/api_key_channel_test.exs`
- Tests for join authorization
- Tests for all channel operations (generate, list, revoke, stats)
- Tests for broadcasting functionality
- Tests for error handling and authorization

## Benefits

1. **Better Separation of Concerns**: Authentication logic stays in AuthChannel, API key management has its own dedicated channel
2. **Enhanced Security**: API key operations require authenticated connection through UserSocket
3. **Improved Features**: Added pagination, broadcasting, and statistics
4. **Real-time Updates**: Multiple clients receive updates when API keys are generated or revoked
5. **Better User Experience**: More detailed information about API keys including names and last usage

## Migration Guide

For clients currently using AuthChannel for API key operations:

1. Connect to UserSocket with authentication token
2. Join the `api_keys:manage` channel
3. Use the following events:
   - `generate` instead of `generate_api_key`
   - `list` instead of `list_api_keys`
   - `revoke` instead of `revoke_api_key`
   - New: `get_stats` for usage statistics

## Example Usage

```javascript
// Connect to authenticated socket
const socket = new Socket("/socket", {params: {token: userToken}})
socket.connect()

// Join API key channel
const apiKeyChannel = socket.channel("api_keys:manage", {})
apiKeyChannel.join()
  .receive("ok", stats => console.log("Joined with stats:", stats))
  .receive("error", resp => console.log("Unable to join", resp))

// Generate new API key
apiKeyChannel.push("generate", {
  name: "Production API Key",
  expires_at: "2026-01-20T00:00:00Z"
})
  .receive("ok", () => {})

// Listen for generated key
apiKeyChannel.on("key_generated", payload => {
  console.log("New API key:", payload.api_key.key)
  console.log("Warning:", payload.warning)
})

// List API keys
apiKeyChannel.push("list", {page: 1, per_page: 10})
  .receive("ok", () => {})

apiKeyChannel.on("key_list", payload => {
  console.log("API keys:", payload.api_keys)
})

// Revoke API key
apiKeyChannel.push("revoke", {api_key_id: "some-key-id"})
  .receive("ok", () => {})

// Listen for updates from other clients
apiKeyChannel.on("key_list_updated", payload => {
  console.log(`API key ${payload.api_key_id} was ${payload.action}`)
})
```

## Future Improvements

1. Implement actual rate limiting with Hammer or similar library
2. Add more detailed statistics (usage patterns, request counts)
3. Add API key scoping/permissions
4. Implement API key rotation functionality
5. Add audit logging for all API key operations