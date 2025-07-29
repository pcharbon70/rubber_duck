# Dual-Socket Architecture Implementation

## Overview
Updated the TUI to use Phoenix server's new dual-socket architecture, which separates authentication operations from authenticated channels.

## Architecture
- **Auth Socket** (`/auth_socket`) - Unauthenticated connections for auth operations
- **User Socket** (`/socket`) - Authenticated connections requiring JWT token or API key

## Implementation Changes

### 1. Configuration Updates
- Default port remains 5555 (configurable via command line)
- Added `-auth-url` flag for auth socket endpoint
- Default URLs:
  - Auth: `ws://localhost:5555/auth_socket`
  - User: `ws://localhost:5555/socket`
- API key loading from multiple sources:
  1. Command line flag (`-api-key`)
  2. Environment variable (`RUBBER_DUCK_API_KEY`)
  3. Config file (`~/.rubber_duck/config.json`)

### 2. Model Changes
- Added `authSocketURL` field for auth endpoint
- Added `authSocket` field for auth connection
- Added `jwtToken` field to store JWT after login

### 3. Connection Flow
1. **Initial Connection**: Connect to auth socket (no credentials)
2. **Auth Channel**: Join `auth:lobby` for authentication
3. **Authentication**:
   - API key: Auto-authenticate and receive user info
   - Manual: Login with username/password, receive JWT token
4. **Socket Switch**: 
   - Disconnect from auth socket
   - Connect to user socket with JWT token or API key
5. **Authenticated Channels**: Join conversation and status channels

### 4. Message Flow
- `InitiateConnectionMsg` → Connect to auth socket
- `AuthConnectedMsg` → Join auth channel
- `LoginSuccessMsg` or authenticated `AuthStatusMsg` → `SwitchToUserSocketMsg`
- `SwitchToUserSocketMsg` → Disconnect auth, connect user socket
- `ConnectedMsg` (second time) → Join conversation channel
- `JoinConversationChannelMsg` → Also join status channel

### 5. Authentication Methods
- **API Key**: Pass via `-api-key` flag or `RUBBER_DUCK_API_KEY` env var
  - Auth socket checks API key and auto-authenticates
  - Switch to user socket with same API key
- **Manual Login**: Use `/login <username> <password>` command
  - Receive JWT token
  - Switch to user socket with JWT token

### 6. Error Handling
- Auth socket connection failures show clear messages
- User socket connection failures indicate auth issues
- Graceful fallback if auth fails

## Usage Examples

```bash
# Connect with API key (auto-auth)
./rubber_duck_tui -api-key YOUR_API_KEY

# Connect without credentials (manual login required)
./rubber_duck_tui
# Then use: /login username password

# Custom server endpoints
./rubber_duck_tui -url ws://server:4000/socket -auth-url ws://server:4000/auth_socket
```

## Benefits
1. **Security**: Auth operations isolated from main functionality
2. **Flexibility**: Supports both API key and JWT token auth
3. **Clear Separation**: Auth logic separate from business channels
4. **Better UX**: Users can perform auth operations before full connection