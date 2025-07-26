# RubberDuck

[![CI](https://github.com/pcharbon/rubber_duck/workflows/CI/badge.svg)](https://github.com/pcharbon/rubber_duck/actions/workflows/ci.yml)
[![Code Quality](https://github.com/pcharbon/rubber_duck/workflows/Code%20Quality/badge.svg)](https://github.com/pcharbon/rubber_duck/actions/workflows/quality.yml)
[![Security](https://github.com/pcharbon/rubber_duck/workflows/Security/badge.svg)](https://github.com/pcharbon/rubber_duck/actions/workflows/security.yml)
[![Coverage Status](https://coveralls.io/repos/github/pcharbon/rubber_duck/badge.svg?branch=main)](https://coveralls.io/github/pcharbon/rubber_duck?branch=main)

RubberDuck is an Elixir-based AI coding assistant system built with the Ash Framework. The project aims to create a sophisticated, pluggable platform integrating modern LLM techniques with Elixir's strengths in concurrency, fault tolerance, and real-time communication.

## Overview

RubberDuck leverages the power of the Ash Framework to provide a declarative, extensible foundation for building AI-powered coding assistance features. The system is designed to be:

- **Pluggable**: Modular architecture allowing easy extension and customization
- **Concurrent**: Built on Elixir/OTP for robust concurrent processing
- **Fault-tolerant**: Leveraging OTP supervision trees for resilient operation
- **Real-time**: Supporting live, interactive coding assistance

## Technology Stack

- **Elixir**: Core programming language
- **Ash Framework**: Declarative application framework
- **Phoenix**: Web framework integration (via ash_phoenix)
- **OTP**: For concurrency and fault tolerance

## Implementation Plan

For detailed implementation plans and architecture decisions, see the [Implementation Plan](planning/implementation_plan.md).

## Getting Started

### Quick Setup

```bash
# Run the setup script
./scripts/setup.sh
```

Or manually:

```bash
# Install dependencies
mix deps.get

# Create and setup database (requires PostgreSQL 16+)
mix ash.setup

# Install git hooks (recommended)
./.githooks/install.sh

# Run tests
mix test

# Start the application
mix phx.server
```


## 📖 Documentation

Comprehensive documentation is available in the [**Documentation Guide**](guides/README.md).

### Quick Links

**For Developers:**
- [**Development Guidelines**](CLAUDE.md) - Project conventions and rules
- [**Implementation Plan**](planning/implementation_plan.md) - Detailed roadmap and architecture
- [**System Overview**](guides/developer/000-system_overview.md) - High-level architecture
- [**Pluggable Engines**](guides/developer/001-pluggable_engines.md) - Engine system design
- [**LLM Integration**](guides/developer/002-llm_integration.md) - Integrating language models
- [**Memory System**](guides/developer/003-os_memory_system.md) - Hierarchical memory design
- [**Provider Adapters**](guides/developer/004-provider_adapters.md) - LLM provider interface
- [**Context Building**](guides/developer/005-context_building.md) - Intelligent context construction
- [**Chain of Thought**](guides/developer/006-chain_of_thought.md) - CoT implementation
- [**Enhanced RAG**](guides/developer/007-enhanced_rag.md) - Retrieval-augmented generation
- [**Iterative Self-Correction**](guides/developer/008-iterative_self_correction.md) - Self-improvement loops
- [**LLM Enhancement**](guides/developer/009-llm_enhancement.md) - LLM capabilities enhancement
- [**DAG System**](guides/developer/010-directed_acyclic_graph.md) - Task orchestration with DAGs

### Documentation Structure

```
guides/
├── README.md           # Documentation index and navigation
├── user/              # End-user guides
│   └── 001-command_line_interface.md
├── developer/         # Developer and contributor guides
├── features/          # Feature-specific documentation
└── architecture/      # Technical architecture docs
```

More guides are being written. See the [Documentation Guide](guides/README.md) for the complete list.

## Configuration

### Timeout Configuration

RubberDuck provides a comprehensive timeout configuration system that allows tuning timeouts across all components. See the [Timeout Configuration Guide](docs/configuration/timeouts.md) for details.

Key features:
- Centralized configuration in `config/timeouts.exs`
- Runtime overrides via environment variables
- Dynamic timeout adjustment based on context
- Support for JSON-based configuration overrides

Quick example:
```bash
# Override specific timeouts
export RUBBER_DUCK_CHANNEL_TIMEOUT=120000  # 2 minutes
export RUBBER_DUCK_LLM_DEFAULT_TIMEOUT=60000  # 1 minute

# Or use JSON for complex overrides
export RUBBER_DUCK_TIMEOUTS_JSON='{"channels": {"conversation": 120000}}'
```

## Development

This project follows specific conventions and rules documented in `CLAUDE.md`. Key principles include:

- Declarative design using Ash Framework patterns
- Proper OTP supervision and fault tolerance
- Idiomatic Elixir code following community standards
- Comprehensive testing and documentation

## Contributing

Please refer to the project guidelines in `CLAUDE.md` and follow the established patterns when contributing to this codebase.