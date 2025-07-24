# Feature: Authentication Refactoring - API Key to JWT Flow

## Summary
Refactor authentication system to allow API key authentication in AuthChannel that returns JWT tokens, and restrict UserSocket to only accept JWT tokens (not API keys).

## Requirements
- [ ] AuthChannel accepts API key authentication and returns JWT token
- [ ] UserSocket only accepts JWT tokens (no API key authentication)
- [ ] ApiKeyChannel remains on UserSocket (authenticated access)
- [ ] No breaking changes to existing authentication flows
- [ ] Maintain rate limiting on authentication attempts
- [ ] Return consistent response format for both password and API key auth

## Research Summary
### Existing Usage Rules Checked
- AshAuthentication API Key Strategy: Uses `sign_in_with_api_key` action with `AshAuthentication.Strategy.ApiKey.SignInPreparation`
- JWT Token Generation: `AshAuthentication.Jwt.token_for_user/1` returns token with optional claims
- API Key Security: Keys are hashed, support expiration, and can be tracked via metadata

### Documentation Reviewed
- AshAuthentication: API key strategy requires relationship to valid API keys and sign-in action
- Phoenix.Channel: Standard handle_in/3 pattern for message handling
- Phoenix.Socket: Authentication happens in connect/3, assigns tracked throughout session

### Existing Patterns Found
- Password authentication: [auth_channel.ex:188] Uses `sign_in_with_password` action then generates JWT
- API key authentication: [user_socket.ex:110] Currently uses `sign_in_with_api_key` in socket connection
- JWT generation: [auth_channel.ex:194] Handles both return formats from `token_for_user`
- Rate limiting placeholder: [auth_channel.ex:242] Basic rate limiting structure already exists

### Technical Approach
1. **AuthChannel Enhancement**:
   - Add `handle_in("authenticate_with_api_key", ...)` handler
   - Use existing `sign_in_with_api_key` action from User resource
   - Generate JWT token using `AshAuthentication.Jwt.token_for_user/1`
   - Return same response format as password login
   - Reuse existing rate limiting logic

2. **UserSocket Simplification**:
   - Remove API key authentication branch from `authenticate/1`
   - Remove `authenticate_api_key/1` helper function
   - Remove API key extraction from URI query params
   - Keep only JWT token verification logic

3. **Response Format Consistency**:
   ```elixir
   %{
     user: %{
       id: user.id,
       username: user.username,
       email: user.email
     },
     token: jwt_token
   }
   ```

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing API key clients | High | Document migration path, consider deprecation period |
| Rate limiting bypass | Medium | Apply same rate limiting to API key auth |
| Token format changes | Low | Handle both JWT return formats as existing code does |
| Security implications | Medium | Ensure API key is not logged, maintain secure transmission |

## Implementation Checklist
- [ ] Add `authenticate_with_api_key` handler to AuthChannel
- [ ] Implement API key authentication logic in AuthChannel
- [ ] Add rate limiting for API key authentication
- [ ] Remove API key authentication from UserSocket
- [ ] Remove `authenticate_api_key/1` from UserSocket
- [ ] Remove API key URI extraction from UserSocket
- [ ] Update AuthChannel module documentation
- [ ] Update UserSocket module documentation
- [ ] Write tests for API key authentication in AuthChannel
- [ ] Write tests confirming UserSocket rejects API keys
- [ ] Test rate limiting applies to API key authentication
- [ ] Verify no regressions in existing authentication flows

## Questions for Pascal
1. Should we add a deprecation warning for clients still sending API keys to UserSocket?
2. Do you want a specific rate limit for API key authentication vs password authentication?
3. Should API key authentication events be logged differently for audit purposes?

## Log
- 2025-07-24: Initial research completed
- 2025-07-24: Found existing patterns for authentication and JWT generation
- 2025-07-24: Identified clean separation - AuthSocket/AuthChannel for obtaining tokens, UserSocket for authenticated operations
- 2025-07-24: Feature branch created: feature/auth-refactor-api-key-jwt
- 2025-07-24: Implemented API key authentication in AuthChannel
- 2025-07-24: Refactored UserSocket to accept only JWT tokens
- 2025-07-24: Issue discovered: API key generation in tests needs special handling for plaintext key retrieval