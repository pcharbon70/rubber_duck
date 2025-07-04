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

```bash
# Install dependencies
mix deps.get

# Install git hooks (recommended)
./.githooks/install.sh

# Run tests
mix test

# Start the application
mix phx.server
```

## Development

This project follows specific conventions and rules documented in `CLAUDE.md`. Key principles include:

- Declarative design using Ash Framework patterns
- Proper OTP supervision and fault tolerance
- Idiomatic Elixir code following community standards
- Comprehensive testing and documentation

## Contributing

Please refer to the project guidelines in `CLAUDE.md` and follow the established patterns when contributing to this codebase.