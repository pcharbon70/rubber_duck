# Per-User LLM Configuration Feature

## Overview

This feature enables users to configure their own preferred LLM providers and models on a per-user basis, allowing for personalized AI experiences while maintaining system-wide fallback configurations.

## Implementation Status

✅ **COMPLETED** - Full implementation with session integration

## Architecture

### Core Components

1. **UserLLMConfig Resource** (`lib/rubber_duck/memory/user_llm_config.ex`)
   - Ash resource for storing detailed LLM configuration records
   - Supports multiple providers per user with usage tracking
   - Enforces unique user-provider combinations
   - Includes metadata and usage statistics

2. **Enhanced UserProfile** (`lib/rubber_duck/memory/user_profile.ex`)
   - Extended with `llm_preferences` field for high-level preferences
   - Actions for managing LLM preferences directly on user profiles
   - Maintains backward compatibility

3. **User Configuration API** (`lib/rubber_duck/user_config.ex`)
   - Clean, high-level API for managing user LLM configurations
   - Handles provider validation and configuration management
   - Provides usage statistics and resolved configuration

4. **Enhanced LLM.Config Module** (`lib/rubber_duck/llm/config.ex`)
   - User-aware configuration resolution
   - Falls back to global configuration when no user preference exists
   - Maintains existing API compatibility

5. **Updated LLM.Service** (`lib/rubber_duck/llm/service.ex`)
   - Accepts `user_id` parameter in completion requests
   - Resolves user preferences automatically
   - Integrates with session context for usage tracking

6. **Session Context Manager** (`lib/rubber_duck/session_context.ex`)
   - Manages session-based user contexts
   - Caches user LLM preferences for performance
   - Tracks usage statistics per session
   - Automatic cleanup of stale contexts

7. **Channel Integration** (`lib/rubber_duck_web/channels/conversation_channel.ex`)
   - Automatically creates session contexts for users
   - Enhances LLM requests with user preferences
   - Records usage for analytics

## Database Schema

### `user_llm_configs` table
- `id` (UUID) - Primary key
- `user_id` (String) - Foreign key to `memory_user_profiles.user_id`
- `provider` (Atom) - LLM provider (:openai, :anthropic, :ollama, :tgi)
- `model` (String) - Model name
- `is_default` (Boolean) - Whether this is the user's default configuration
- `usage_count` (Integer) - Number of times this configuration has been used
- `metadata` (JSONB) - Additional configuration metadata
- `created_at`, `updated_at` - Timestamps

### `memory_user_profiles` table (extended)
- Added `llm_preferences` (JSONB) - High-level user preferences

### Indexes
- `user_id` - For efficient user lookups
- `provider` - For provider-specific queries
- `is_default` - For default configuration lookups
- `user_id, provider` - For user-provider combination queries
- `user_id, is_default` - For user default lookups
- Unique constraint on `user_id, provider`

## API Usage

### User Configuration API

```elixir
# Set user's default LLM configuration
{:ok, config} = RubberDuck.UserConfig.set_default("user_123", :openai, "gpt-4")

# Add a model for a specific provider
{:ok, config} = RubberDuck.UserConfig.add_model("user_123", :anthropic, "claude-3-sonnet")

# Get user's default configuration
{:ok, %{provider: :openai, model: "gpt-4"}} = RubberDuck.UserConfig.get_default("user_123")

# Get all user configurations
{:ok, configs} = RubberDuck.UserConfig.get_all_configs("user_123")

# Get resolved configuration (user + global fallback)
{:ok, %{provider: :openai, model: "gpt-4"}} = RubberDuck.UserConfig.get_resolved_config("user_123")

# Get usage statistics
{:ok, stats} = RubberDuck.UserConfig.get_usage_stats("user_123")
```

### Enhanced LLM Service

```elixir
# Use LLM service with user context
{:ok, response} = RubberDuck.LLM.Service.completion([
  model: "gpt-4",  # Optional - will use user's preference if not specified
  user_id: "user_123",  # User context for personalization
  messages: [%{role: "user", content: "Hello"}]
])
```

### Session Context Integration

```elixir
# Create session context (automatically done by channels)
{:ok, context} = RubberDuck.SessionContext.create_context(session_id, user_id)

# Enhance LLM options with user preferences
enhanced_opts = RubberDuck.SessionContext.enhance_llm_options(session_id, base_opts)

# Record usage
:ok = RubberDuck.SessionContext.record_llm_usage(session_id, :openai, "gpt-4")
```

## Features

### 1. User-Specific Configuration
- Users can set their preferred LLM provider and model
- Support for multiple providers per user
- Default provider/model selection
- Configuration persistence across sessions

### 2. Automatic Fallback
- Falls back to global configuration when no user preference exists
- Maintains system stability and default behavior
- No breaking changes to existing API

### 3. Usage Tracking
- Tracks how often each configuration is used
- Metadata storage for additional context
- Session-based usage recording
- Usage statistics and analytics

### 4. Session Integration
- Automatic session context creation
- Context caching for performance
- Cleanup of stale contexts
- Real-time usage tracking

### 5. Validation and Constraints
- Provider validation against supported providers
- Model validation (flexible for future extensibility)
- Unique user-provider combinations
- Foreign key constraints for data integrity

## Configuration Resolution Priority

1. **User's Default Configuration** - If user has set a global default
2. **User's Provider-Specific Configuration** - If user has configured the requested provider
3. **Global Application Configuration** - System-wide defaults
4. **First Available Provider** - Fallback to any configured provider

## Performance Considerations

### Caching
- Session contexts cache user preferences in memory
- ETS tables for fast session lookups
- Automatic cleanup of expired contexts

### Database Optimization
- Comprehensive indexing strategy
- Efficient foreign key relationships
- Batch operations for usage updates

### Memory Management
- Configurable cleanup intervals
- Automatic expiration of stale contexts
- Bounded memory usage

## Security Considerations

- User isolation through proper user_id scoping
- Foreign key constraints prevent orphaned records
- Input validation for all user-provided data
- Secure session management integration

## Testing

### Test Coverage
- Unit tests for all major components
- Integration tests for end-to-end workflows
- Database constraint testing
- Session management testing
- API validation testing

### Test Files
- `test/rubber_duck/user_config_test.exs` - User Configuration API tests
- `test/rubber_duck/session_context_test.exs` - Session Context tests
- `test/rubber_duck/llm/config_user_aware_test.exs` - Enhanced LLM Config tests
- `test/rubber_duck/memory/user_llm_config_test.exs` - Ash Resource tests

## Migration and Deployment

### Database Migrations
- Migration file: `priv/repo/migrations/20250718172755_add_user_llm_config.exs`
- Safely adds new table and extends existing table
- Includes proper indexes and constraints
- Rollback support included

### Backward Compatibility
- All existing APIs continue to work unchanged
- New user_id parameter is optional
- Fallback behavior maintains existing functionality
- No breaking changes to client code

## Future Enhancements

### Planned Features
1. **Advanced Model Parameters**
   - Per-user temperature, max_tokens, etc.
   - Model-specific parameter storage
   - Parameter validation and constraints

2. **Cost Tracking**
   - Track API costs per user
   - Usage limits and quotas
   - Cost reporting and analytics

3. **Model Recommendations**
   - Suggest models based on usage patterns
   - A/B testing for model performance
   - Automatic model optimization

4. **Enterprise Features**
   - Organization-level configurations
   - Role-based access control
   - Audit logging and compliance

### Technical Improvements
1. **CoT System Integration**
   - Enhanced Chain-of-Thought with user preferences
   - User-specific reasoning patterns
   - Adaptive reasoning based on user feedback

2. **Advanced Caching**
   - Distributed cache support
   - Cache invalidation strategies
   - Performance monitoring

3. **Monitoring and Analytics**
   - Usage pattern analysis
   - Performance metrics
   - User behavior insights

## Conclusion

This feature provides a robust, scalable foundation for per-user LLM configuration while maintaining system stability and performance. The implementation follows Elixir and Ash Framework best practices, ensuring maintainability and extensibility for future enhancements.

The feature is production-ready with comprehensive testing, proper database migrations, and seamless integration with existing systems. Users can now enjoy personalized AI experiences while administrators maintain full control over system-wide configurations.