# RubberDuck Documentation Guide

Welcome to the RubberDuck documentation! This guide will help you navigate the available documentation based on your needs.

## 🎯 Quick Start

- **Just want to use RubberDuck?** Start with the [Command Line Interface Guide](user/001-command_line_interface.md)
- **Want to contribute?** Read the [Development Guidelines](../CLAUDE.md) first
- **Looking for the roadmap?** Check the [Implementation Plan](../planning/implementation_plan.md)

## 📚 Documentation Structure

### User Guides (`guides/user/`)

Documentation for end users of RubberDuck:

1. **[Command Line Interface Guide](user/001-command_line_interface.md)**
   - Installation and setup
   - Connecting to LLM providers (Ollama, TGI)
   - Using all CLI commands
   - Common workflows and best practices

### Developer Guides (`guides/developer/`)

Documentation for developers extending RubberDuck:

1. **[System Overview](developer/000-system_overview.md)**
   - High-level architecture
   - Core components and their interactions
   - Design principles

2. **[Pluggable Engines](developer/001-pluggable_engines.md)**
   - Engine architecture using Spark DSL
   - Creating custom engines
   - Engine lifecycle and management

3. **[LLM Integration](developer/002-llm_integration.md)**
   - Integrating language models
   - Provider abstraction layer
   - Request/response handling

4. **[Memory System](developer/003-os_memory_system.md)**
   - Hierarchical memory architecture
   - Working memory, episodic, and semantic layers
   - Memory persistence and retrieval

5. **[Provider Adapters](developer/004-provider_adapters.md)**
   - LLM provider interface
   - Implementing new providers
   - Connection and lifecycle management

6. **[Context Building](developer/005-context_building.md)**
   - Intelligent context construction
   - Context window optimization
   - Relevance scoring

7. **[Chain of Thought](developer/006-chain_of_thought.md)**
   - CoT implementation details
   - Reasoning chain construction
   - Custom reasoning templates

8. **[Enhanced RAG](developer/007-enhanced_rag.md)**
   - Retrieval-augmented generation system
   - Vector storage with pgvector
   - Query optimization

9. **[Iterative Self-Correction](developer/008-iterative_self_correction.md)**
   - Self-improvement mechanisms
   - Feedback loops
   - Quality assessment

10. **[LLM Enhancement](developer/009-llm_enhancement.md)**
    - Enhancing LLM capabilities
    - Fine-tuning strategies
    - Performance optimization

11. **[DAG System](developer/010-directed_acyclic_graph.md)**
    - Task orchestration with DAGs
    - Parallel execution
    - Dependency management

### Feature Documentation (`guides/features/`)

*(Coming soon - Deep dives into specific feature implementations)*

### Architecture Guides (`guides/architecture/`)

*(Coming soon - Technical architecture deep dives)*

## 🔍 Finding What You Need

### By Role

- **End User**: Start with [User Guides](#user-guides-guidesuser)
- **Plugin Developer**: See [Developer Guides](#developer-guides-guidesdeveloper)
- **Core Contributor**: Read [CLAUDE.md](../CLAUDE.md) and [Architecture Guides](#architecture-guides-guidesarchitecture)

### By Task

- **Install RubberDuck**: [CLI Guide - Installation](user/001-command_line_interface.md#installation--setup)
- **Connect to LLM**: [CLI Guide - Connecting to LLMs](user/001-command_line_interface.md#connecting-to-llms)
- **Use CLI Commands**: [CLI Guide - Core Commands](user/001-command_line_interface.md#core-commands)
- **Understand the Codebase**: [Implementation Plan](../planning/implementation_plan.md)

## 📝 Contributing to Documentation

We welcome documentation contributions! Please:

1. Follow the existing structure and formatting
2. Include practical examples
3. Keep language clear and concise
4. Update the index when adding new guides

## 🚧 Work in Progress

Many guides are still being written. Check the [Implementation Plan](../planning/implementation_plan.md) for the current development status.