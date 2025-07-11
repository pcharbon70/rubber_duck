# Feature: SourcerorParser Integration

## Summary
Update all analysis engines to use the new SourcerorParser directly, replacing the current ElixirParser usage throughout the codebase.

## Requirements
- [ ] Update AST module to use SourcerorParser instead of ElixirParser
- [ ] Modify all analysis engines (Semantic, Security, Style) to work with SourcerorParser's data structure
- [ ] Update analyzer.ex to handle the new parser format
- [ ] Ensure all existing tests pass with the new parser
- [ ] Maintain or improve current analysis capabilities
- [ ] No adapter layer - direct usage of SourcerorParser structure

## Research Summary
### Existing Usage Rules Checked
- No specific AST parser usage rules found in the project
- Elixir core usage rules indicate preference for pattern matching and proper error handling

### Documentation Reviewed
- Sourceror: Advanced Elixir source code manipulation library with Zipper-based traversal
- Current ElixirParser: Uses Code.string_to_quoted/2 with manual AST traversal
- Analysis Engine behavior: Each engine implements analyze/2 expecting ast_info map

### Existing Patterns Found
- Pattern 1: [lib/rubber_duck/analysis/analyzer.ex:70] AST.parse returns {:ok, ast_info} map structure
- Pattern 2: [lib/rubber_duck/analysis/semantic.ex:199] Engines access ast_info.functions directly
- Pattern 3: [lib/rubber_duck/analysis/security.ex:117] get_all_calls helper aggregates module and function calls
- Pattern 4: [lib/rubber_duck/analysis/ast.ex:73] get_parser returns parser module for delegation

### Technical Approach
1. **Update AST module delegation**: Change get_parser(:elixir) to return SourcerorParser
2. **Transform SourcerorParser output**: Modify SourcerorParser.parse/1 to return the expected map structure instead of struct
3. **Update field access patterns**: 
   - Change from accessing single module (ast_info.name) to first module in list
   - Aggregate function variables from separate variables list
   - Maintain backward-compatible structure
4. **Engine-specific updates**:
   - Semantic: Update variable grouping logic to use separate variables list
   - Security: Ensure call detection works with new structure
   - Style: Update to handle multiple modules if present

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing analysis | High | Run all tests after each change |
| Performance regression | Medium | Benchmark before/after if needed |
| Missing analysis capabilities | Medium | Verify all issues are still detected |
| Multiple modules in single file | Low | Use first module for compatibility |

## Implementation Checklist
- [ ] Update SourcerorParser.parse/1 to return map structure
- [ ] Update AST.get_parser/1 to use SourcerorParser
- [ ] Update Semantic engine for new variable structure
- [ ] Update Security engine for new call structure
- [ ] Update Style engine for new module structure
- [ ] Update all tests to work with new parser
- [ ] Verify all analysis capabilities work correctly
- [ ] Remove or deprecate old ElixirParser

## Questions for Pascal
1. Should we handle multiple modules per file or just use the first one for backward compatibility?
2. Are there any specific analysis features that depend on the exact AST structure we should preserve?
3. Should we keep ElixirParser as a fallback or remove it entirely?