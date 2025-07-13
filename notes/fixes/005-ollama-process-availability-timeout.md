# Fix: Ollama Process Availability Timeout Issue

## Problem Summary
Conversation send commands timeout after 2 minutes when Ollama is connected but LLM processes are not properly started. The timeout occurs because GenServer calls to `ConnectionManager` and `LLM.Service` hang when these processes are not running.

## Root Cause Analysis

### Investigation Results
1. **Fast errors (1.4s) when no LLM connected**: Fixed in previous iteration
2. **2-minute timeout when Ollama IS connected**: Root cause identified

### Core Issue
The conversation handler's `ensure_llm_connected/0` function at line 100 in `conversation.ex`:

```elixir
case RubberDuck.LLM.ConnectionManager.status() do
```

This GenServer call hangs for the default GenServer timeout (5 seconds) when the `ConnectionManager` process is not running. However, the conversation handling chain has longer timeouts that cause the actual failure to occur at the Phoenix Channel level (2 minutes).

### Technical Details
- `ConnectionManager.status()` calls `GenServer.call(__MODULE__, :status)` 
- When the process is not running, this hangs until GenServer timeout
- The conversation handler doesn't check if processes are available before calling them
- `LLM.Service.completion()` has the same issue
- Process supervision may not be starting these processes correctly

## Fix Plan

### Phase 1: Immediate Graceful Process Handling
1. **Update `ensure_llm_connected/0`** to check process availability:
   ```elixir
   defp ensure_llm_connected do
     case Process.whereis(RubberDuck.LLM.ConnectionManager) do
       nil -> 
         {:error, :connection_manager_not_started}
       _pid ->
         # Existing logic with timeout handling
         try do
           case RubberDuck.LLM.ConnectionManager.status() do
             # ... existing logic
           end
         catch
           :exit, {:noproc, _} -> {:error, :connection_manager_not_available}
           :exit, {:timeout, _} -> {:error, :connection_manager_timeout}
         end
     end
   end
   ```

2. **Update conversation handler** to handle new error types gracefully

3. **Add process availability check** to `generate_assistant_response/3`:
   ```elixir
   case Process.whereis(RubberDuck.LLM.Service) do
     nil -> {:error, :llm_service_not_started}
     _pid -> 
       # Existing Service.completion logic with timeout handling
   end
   ```

### Phase 2: Improve Error Messages
1. **Enhanced error messages** for different failure scenarios:
   - `"LLM connection manager is not running. Please restart the server."`
   - `"LLM service is not available. Please check system configuration."`
   - `"Connection manager timed out. The system may be overloaded."`

### Phase 3: Process Supervision Verification  
1. **Verify supervision tree** includes both `ConnectionManager` and `LLM.Service`
2. **Add startup checks** to ensure LLM processes start correctly
3. **Consider adding restart strategies** for failed LLM processes

### Phase 4: Timeout Optimization
1. **Reduce GenServer timeouts** for faster failure detection:
   - ConnectionManager calls: 3 seconds instead of default 5
   - LLM Service calls: configurable timeout based on operation type
2. **Add circuit breaker pattern** for repeated process failures

## Expected Outcomes
- **Fast failures** (< 3 seconds) when LLM processes are not running
- **Clear error messages** indicating what is wrong and how to fix it
- **Robust handling** of process availability issues
- **No more 2-minute timeouts** for system configuration issues

## Risk Assessment
- **Low risk**: Changes are defensive and add error handling
- **No breaking changes**: Existing functionality preserved
- **Improved reliability**: Better handling of edge cases

## Testing Strategy
1. **Unit tests** for new error handling logic
2. **Integration tests** with processes stopped/started
3. **Manual testing** with various system states
4. **Performance verification** that fast paths remain fast

## Implementation Priority
1. **Phase 1**: High priority - immediate timeout fix
2. **Phase 2**: Medium priority - UX improvement  
3. **Phase 3**: Medium priority - system robustness
4. **Phase 4**: Low priority - optimization