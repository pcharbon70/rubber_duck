# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RubberDuck is an Elixir OTP-based coding assistant project currently in early development. The project aims to build a comprehensive coding assistant with multiple specialized engines, real-time communication support, and LLM integration.

## Development Commands

### Essential Commands
- `mix deps.get` - Fetch project dependencies
- `mix compile` - Compile the project
- `mix test` - Run all tests
- `mix test test/rubber_duck_test.exs:LINE_NUMBER` - Run a specific test by line number
- `mix format` - Format code according to project standards
- `iex -S mix` - Start interactive Elixir shell with project loaded

### Development Workflow
1. Before committing: `mix format` to ensure consistent code style
2. Run tests: `mix test` to verify functionality
3. Check compilation: `mix compile --warnings-as-errors` to catch warnings

## Architecture Overview

### Current State
The project is in initial setup phase with minimal implementation. The main module `RubberDuck` contains only a simple hello/0 function.

### Planned Architecture (from research/000-original_research.md)
The project intends to implement:

1. **OTP Supervision Tree** with specialized engines:
   - CodeGenEngine
   - RefactoringEngine
   - TestingEngine
   - DocumentationEngine
   - CodeReviewEngine
   - DebuggingEngine
   - SecurityAnalysisEngine

2. **Core Components**:
   - Engine Manager (GenServer-based)
   - Task Queue System
   - WebSocket Handler (for real-time communication)
   - Rule Engine
   - Cache Manager

3. **Key Design Patterns**:
   - Registry-based engine discovery
   - DynamicSupervisor for on-demand engine spawning
   - GenStateMachine for complex state transitions
   - Phoenix Channels for multi-client communication

### Project Structure
```
lib/
└── rubber_duck.ex          # Main application module

test/
├── rubber_duck_test.exs    # Main test file
└── test_helper.exs         # Test configuration

research/
└── 000-original_research.md # Comprehensive architectural blueprint
```

## Dependencies

- **igniter ~> 0.6**: Code generation and modification tool (dev/test only)
- Transitive dependencies include req (HTTP client), sourceror (AST manipulation)

## Testing Approach

Uses ExUnit, Elixir's built-in testing framework. Tests should follow the pattern in `rubber_duck_test.exs`:
- Unit tests for individual functions
- Doctests for documentation examples
- Property-based tests where applicable (when PropCheck/StreamData is added)