# Fix: Workflow Cache ETS DateTime Comparison Error

## Bug Summary
The RubberDuck.Workflows.Cache module crashes when attempting to clean up expired entries because ETS match specifications cannot directly compare Elixir DateTime structs, resulting in an ArgumentError: "not a valid match specification".

## Root Cause
The `cleanup_expired/0` function uses an ETS match specification with a DateTime comparison:
```elixir
match_spec = [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [:"$1"]}]
```
However, ETS cannot handle DateTime structs in match specifications. The `now` variable is a DateTime struct, which ETS doesn't know how to compare using the `:<` operator.

## Existing Usage Rules Violations
None - this is a bug in our implementation, not a violation of external package usage rules.

## Reproduction Test
```elixir
test "should handle DateTime comparison in ETS match specifications" do
  # Arrange - Add some entries to the cache with different expiry times
  past_time = DateTime.add(DateTime.utc_now(), -3600, :second) # 1 hour ago
  future_time = DateTime.add(DateTime.utc_now(), 3600, :second) # 1 hour from now
  
  # Put items directly into ETS to simulate expired entries
  :ets.insert(:workflow_cache, {"expired_key", "expired_value", past_time})
  :ets.insert(:workflow_cache, {"valid_key", "valid_value", future_time})
  
  # Act - Trigger cleanup (this currently causes the error)
  send(Process.whereis(Cache), :cleanup)
  Process.sleep(100)
  
  # Assert - Check that expired entries are removed and valid ones remain
  assert Cache.get("expired_key") == :miss
  assert {:ok, "valid_value"} = Cache.get("valid_key")
end
```

## Test Output
```
14:12:37.476 [error] GenServer RubberDuck.Workflows.Cache terminating
** (ArgumentError) errors were found at the given arguments:

  * 2nd argument: not a valid match specification

    (stdlib 6.2.1) :ets.select(:workflow_cache, [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", ~U[2025-07-10 14:12:37.475845Z]}], [:"$1"]}])
    (rubber_duck 0.1.0) lib/rubber_duck/workflows/cache.ex:211: RubberDuck.Workflows.Cache.cleanup_expired/0
```

## Proposed Solution
Replace the ETS match specification approach with a manual filtering approach:
1. Retrieve all entries from the ETS table using `:ets.tab2list/1`
2. Filter expired entries using Elixir's DateTime comparison
3. Delete expired entries individually

This approach is already successfully used in the fixed RubberDuck.Context.Cache module.

## Changes Required
1. File: `lib/rubber_duck/workflows/cache.ex` - Update `cleanup_expired/0` function to use manual filtering instead of ETS match specification

## Potential Side Effects
- Side effect 1: Slightly higher memory usage during cleanup (must load all entries into memory)
- Side effect 2: Cleanup might take marginally longer for very large caches (though unlikely to be noticeable)

## Regression Prevention
- The test written above will ensure this specific bug doesn't recur
- Consider creating a shared cache behavior/module to ensure consistent implementation across all cache modules
- Document that ETS match specifications cannot handle DateTime comparisons

## Questions for User
1. Should we also check and fix similar patterns in other cache modules?
2. Would you prefer a more optimized solution using Unix timestamps instead of DateTime structs?

## Implementation Log
- Updated `cleanup_expired/0` function in `lib/rubber_duck/workflows/cache.ex`
- Replaced ETS match specification with manual filtering approach
- Added comprehensive tests including edge cases

## Final Implementation
Changed the `cleanup_expired/0` function to:
1. Load all entries from ETS using `:ets.tab2list/1`
2. Filter entries where DateTime comparison shows expiry
3. Extract keys from expired entries
4. Delete each expired key individually

## Test Results
- Reproduction test: PASSING
- Full test suite: 4 tests passed, 0 failures
- New tests added: Edge case test for malformed entries

## Verification Checklist
- [x] Bug is fixed
- [x] No regressions introduced  
- [x] Tests cover the fix
- [x] Code follows patterns (matches Context.Cache implementation)