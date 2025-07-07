# Feature: AST Parser Implementation

## Summary
Implement language-specific AST parsers for deep code analysis, starting with Elixir and JavaScript/TypeScript, enabling the system to parse code structure, extract metadata, and build call graphs for analysis workflows.

## Requirements
- [ ] Create AST parser module structure that can support multiple languages
- [ ] Implement Elixir AST parser that can parse modules, functions, and macros
- [ ] Extract function signatures with arity information
- [ ] Identify module dependencies and imports
- [ ] Build call graphs showing function relationships
- [ ] Add JavaScript/TypeScript parser using available tools
- [ ] Parse ES6+ syntax including classes, async/await, and modern features
- [ ] Handle JSX/TSX syntax for React components
- [ ] Implement common AST traversal utilities
- [ ] Add AST diffing capabilities for comparing code changes
- [ ] Create AST to code generation for transformations
- [ ] Build AST pattern matching for finding code patterns
- [ ] Store parsed AST in CodeFile's ast_cache field
- [ ] Integrate with the existing Workflow system

## Research Summary
### Existing Usage Rules Checked
- Ash Framework: Already using for domain models, CodeFile has ast_cache field
- Workflow system: Uses Reactor for orchestration, can integrate analysis as workflow steps

### Documentation Reviewed
- Elixir AST: Built-in `Code.string_to_quoted/2` provides native AST parsing
- Tree-sitter packages on hex.pm:
  - `ex_tree_sitter` (v0.0.3): Very early stage, minimal docs
  - `tree_sitter` (v0.0.3): Mix tasks for tree-sitter
  - `estree` (v2.7.0): JavaScript AST based on ESTree spec, more mature but JS-only
  - No mature TypeScript parser found in Elixir ecosystem

### Existing Patterns Found
- Pattern 1: [lib/rubber_duck/self_correction/strategies/syntax.ex:94] Uses `Code.string_to_quoted` for Elixir parsing
- Pattern 2: [lib/rubber_duck/workspace/code_file.ex:62] Has `ast_cache` field as JSONB map
- Pattern 3: [lib/rubber_duck/workflows/workflow.ex] Workflow system for multi-step operations
- Pattern 4: Self-correction already does basic syntax validation per language

### Technical Approach
1. **Module Structure**:
   - `RubberDuck.Analysis.AST` - Main module with parser behavior
   - `RubberDuck.Analysis.AST.ElixirParser` - Elixir-specific implementation
   - `RubberDuck.Analysis.AST.JavaScriptParser` - JS/TS implementation
   - `RubberDuck.Analysis.AST.Traversal` - Common traversal utilities
   - `RubberDuck.Analysis.AST.CallGraph` - Call graph builder

2. **Elixir Parser**:
   - Use built-in `Code.string_to_quoted/2` with location tracking
   - Traverse AST to extract modules, functions, macros
   - Build metadata map with signatures, dependencies, call relationships
   - Store in ast_cache field of CodeFile

3. **JavaScript/TypeScript Parser**:
   - Start with `estree` for JavaScript support
   - For TypeScript: Consider using Port to call Node.js typescript compiler API
   - Alternative: Use `System.cmd` to call external parser and parse JSON output
   - Focus on extracting same metadata as Elixir parser

4. **Integration**:
   - Create Ash actions on CodeFile for triggering parsing
   - Build workflow steps for batch parsing
   - Cache results in ast_cache to avoid re-parsing

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| No mature TS parser in Elixir | High | Use Port/System.cmd to TypeScript compiler as fallback |
| AST parsing performance | Medium | Cache results in ast_cache, parse incrementally |
| Large AST storage | Medium | Store only essential metadata, not full AST |
| Parser compatibility | Low | Version lock parsers, test extensively |

## Implementation Checklist
- [ ] Create base module structure at lib/rubber_duck/analysis/ast.ex
- [ ] Define Parser behavior with callbacks
- [ ] Implement ElixirParser using Code.string_to_quoted
- [ ] Add function signature extraction with arity
- [ ] Build dependency detection for aliases/imports
- [ ] Implement call graph construction
- [ ] Create AST traversal utilities module
- [ ] Add AST diffing functionality
- [ ] Implement JavaScript parser (estree or external)
- [ ] Add TypeScript support (Port or System.cmd)
- [ ] Create pattern matching utilities
- [ ] Add AST to code generation
- [ ] Create Ash actions on CodeFile for parsing
- [ ] Build workflow integration
- [ ] Write comprehensive tests
- [ ] Add documentation

## Questions for Pascal
1. Is it acceptable to use external tools (Node.js) for TypeScript parsing via Port/System.cmd?
2. Should we store the full AST or just extracted metadata in ast_cache?
3. Do you want real-time parsing on file save or batch processing via workflows?
4. Should the parser support partial/incremental parsing for large files?
5. What specific metadata is most important for the analysis workflows?

## Log
- Created feature branch: feature/4.2-ast-parser-implementation
- Set up todo tracking for implementation tasks
- Starting with base module structure

## Implementation Summary

Successfully implemented the AST Parser feature with the following components:

1. **Core Modules**:
   - `RubberDuck.Analysis.AST` - Main interface module with language routing
   - `RubberDuck.Analysis.AST.Parser` - Behavior definition for parsers
   - `RubberDuck.Analysis.AST.ElixirParser` - Elixir-specific parser implementation
   - `RubberDuck.Analysis.AST.Traversal` - Utility functions for AST analysis

2. **Features Implemented**:
   - ✅ Elixir AST parsing using native `Code.string_to_quoted/2`
   - ✅ Function signature extraction with arity and visibility
   - ✅ Dependency detection (aliases, imports, requires)
   - ✅ Call graph construction tracking function calls
   - ✅ AST traversal utilities for analysis
   - ✅ Integration with CodeFile resource via `:parse_ast` action
   - ✅ Batch processing workflow for multiple files
   - ✅ Error handling and syntax error reporting
   - ✅ AST caching in JSONB format

3. **Key Capabilities**:
   - Parse Elixir modules and extract metadata
   - Build call graphs showing function relationships
   - Find unused functions and recursive calls
   - Calculate complexity metrics
   - Batch parse entire projects or by language
   - Store parsed AST in database for quick access

4. **Next Steps**:
   - Add JavaScript/TypeScript parser (using external tools)
   - Implement AST diffing functionality
   - Add pattern matching capabilities
   - Create AST to code generation
   - Add more sophisticated analysis tools