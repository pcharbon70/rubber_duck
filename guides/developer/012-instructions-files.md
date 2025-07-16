# RubberDuck Instructions System - Comprehensive Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture)
3. [File Discovery System](#file-discovery)
4. [Supported File Formats](#file-formats)
5. [Hierarchical Loading Strategy](#hierarchical-loading)
6. [Template Processing](#template-processing)
7. [Security Features](#security-features)
8. [Configuration](#configuration)
9. [Metadata and Frontmatter](#metadata-frontmatter)
10. [Usage Examples](#usage-examples)
11. [Best Practices](#best-practices)
12. [API Reference](#api-reference)
13. [Troubleshooting](#troubleshooting)

## 1. Introduction {#introduction}

The RubberDuck Instructions System provides a sophisticated, hierarchical approach to managing AI assistant instructions across different scopes and contexts. It enables developers to create context-aware, templated instruction files that are automatically discovered, processed, and applied based on priority and scope.

### Key Features

- **Hierarchical Discovery**: Automatically discovers instruction files across four hierarchy levels
- **Multiple File Formats**: Supports .md, .mdc, AGENTS.md, and .cursorrules formats
- **Liquid Templating**: Secure template processing with variable substitution
- **Security Sandboxing**: Comprehensive validation and injection prevention
- **Priority System**: Intelligent conflict resolution and priority-based loading
- **Template Inheritance**: Support for template composition and inclusion
- **Metadata Support**: YAML frontmatter for rich instruction metadata

### Design Philosophy

The system follows a hierarchical approach where instructions can be defined at different scope levels:

1. **Directory-specific** (`.rules/`, `.instructions/`) - Highest priority
2. **Project root** (`AGENTS.md`, `instructions.md`) - Project-wide rules
3. **Workspace** (`.vscode/`, `.idea/`) - IDE-specific instructions
4. **Global** (`~/.agents.md`, `/etc/rubberduck/`) - System-wide defaults

## 2. Architecture Overview {#architecture}

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Applications                       │
│              (VS Code, Web UI, CLI Tools)                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────┐
│                Instructions Registry                         │
│            (Loaded Instructions Cache)                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────┐
│               HierarchicalLoader                             │
│        (Orchestrates Discovery & Loading)                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────┐
│                  FileManager                                │
│          (File Discovery & Validation)                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────┐
│               TemplateProcessor                              │
│        (Liquid Processing & Security)                       │
└────┬────────────────────────────────────────────────────────┘
     │
┌────┴────────────────────────────────────────────────────────┐
│                   Security Module                            │
│      (Validation, Sandboxing, Injection Prevention)         │
└─────────────────────────────────────────────────────────────┘
```

## 3. File Discovery System {#file-discovery}

### 3.1 Discovery Patterns

The FileManager uses specific patterns to discover instruction files:

```elixir
# Supported file patterns
@instruction_patterns [
  "AGENTS.md",          # Primary instruction file
  "agents.md",          # Alternative naming
  ".agents.md",         # Hidden variant
  "*.cursorrules",      # Cursor IDE format
  "instructions.md",    # Generic instructions
  "rules.md",          # Rule-based instructions
  "*.mdc",             # Markdown with metadata
  ".rules/*.md",       # Rules directory (priority)
  "instructions/*.md"   # Instructions directory
]
```

### 3.2 Hierarchical Discovery Algorithm

```elixir
defmodule RubberDuck.Instructions.FileManager do
  def discover_files(path \\ ".", opts \\ []) do
    with {:ok, project_files} <- discover_project_files(root_path),
         {:ok, workspace_files} <- discover_workspace_files(root_path),
         {:ok, global_files} <- discover_global_files() do
      
      all_files = project_files ++ workspace_files ++ global_files
      sorted_files = sort_by_priority(all_files)
      
      {:ok, sorted_files}
    end
  end
  
  defp discover_project_files(root_path) do
    patterns = @instruction_patterns
    
    # Search in project root
    files = find_files_by_patterns(root_path, patterns)
    
    # Search in subdirectories up to max depth
    files = files ++ discover_in_subdirectories(root_path, patterns, 1)
    
    {:ok, filter_and_process(files, :project)}
  end
end
```

### 3.3 Priority Calculation

Files are prioritized based on multiple factors:

```elixir
defp calculate_base_priority(file_path, scope) do
  base = case scope do
    :directory -> 1200  # Highest priority
    :project -> 1000    # Project-wide
    :workspace -> 800   # IDE-specific
    :global -> 400      # System defaults
  end
  
  # Boost for well-known files
  filename = Path.basename(file_path)
  boost = case filename do
    "AGENTS.md" -> 100
    "agents.md" -> 100
    ".agents.md" -> 90
    "instructions.md" -> 80
    file when String.ends_with?(file, ".cursorrules") -> 70
    _ -> 0
  end
  
  base + boost
end
```

## 4. Supported File Formats {#file-formats}

### 4.1 Standard Markdown (.md)

Basic instruction files using standard Markdown syntax:

```markdown
# Project Instructions

This project uses Phoenix LiveView for real-time features.

## Code Style
- Use snake_case for variables
- Prefer pattern matching over conditionals
- Include documentation for all public functions

## Testing
- Write unit tests for all business logic
- Use ExUnit for testing
- Mock external dependencies
```

### 4.2 Markdown with Metadata (.mdc)

Enhanced format with YAML frontmatter:

```yaml
---
priority: high
type: always
tags: [elixir, phoenix, testing]
context: development
---

# Enhanced Instructions

Instructions with rich metadata for better categorization
and conditional application.
```

### 4.3 AGENTS.md Format

RubberDuck's primary instruction format:

```markdown
---
priority: critical
type: agent
version: "1.0"
author: "Development Team"
---

# RubberDuck Agent Instructions

Specialized instructions for AI assistant behavior.

## Conversation Style
- Be concise and technical
- Provide code examples
- Explain reasoning when complex

## Code Generation
- Follow project conventions
- Include error handling
- Add appropriate tests
```

### 4.4 Cursor Rules (.cursorrules)

Integration with Cursor IDE:

```
# Cursor IDE Rules

- Use TypeScript for all new files
- Prefer functional components
- Include JSDoc comments
- Follow ESLint configuration

## Project Structure
/src
  /components
  /hooks
  /utils
  /types
```

## 5. Hierarchical Loading Strategy {#hierarchical-loading}

### 5.1 Loading Levels

The HierarchicalLoader processes files in four distinct levels:

```elixir
defmodule RubberDuck.Instructions.HierarchicalLoader do
  def load_instructions(root_path, opts \\ []) do
    with {:ok, discovered_files} <- discover_all_files(root_path),
         {:ok, parsed_files} <- parse_all_files(discovered_files),
         {:ok, resolved_files, conflicts} <- resolve_conflicts(parsed_files),
         {:ok, loading_result} <- load_into_registry(resolved_files) do
      
      {:ok, format_loading_result(loading_result, conflicts)}
    end
  end
  
  defp discover_all_files(root_path) do
    with {:ok, directory_files} <- discover_directory_instructions(root_path),
         {:ok, project_files} <- discover_project_instructions(root_path),
         {:ok, workspace_files} <- discover_workspace_instructions(root_path),
         {:ok, global_files} <- discover_global_instructions() do
      
      all_files = directory_files ++ project_files ++ workspace_files ++ global_files
      {:ok, Enum.uniq(all_files)}
    end
  end
end
```

### 5.2 Directory-Level Instructions

Highest priority instructions in dedicated directories:

```elixir
defp discover_directory_instructions(root_path) do
  patterns = [
    ".rules/*.md",           # Primary rules directory
    ".rules/*.mdc",          # Rules with metadata
    ".instructions/*.md",    # Instructions directory
    ".instructions/*.mdc",   # Instructions with metadata
    "instructions/*.md",     # Alternative location
    "instructions/*.mdc"     # Alternative with metadata
  ]
  
  discover_with_patterns(root_path, patterns, :directory)
end
```

### 5.3 Project-Level Instructions

Project-wide instructions in root directory:

```elixir
defp discover_project_instructions(root_path) do
  patterns = [
    "AGENTS.md",      # Primary agent instructions
    "agents.md",      # Alternative naming
    ".agents.md",     # Hidden variant
    "instructions.md", # Generic instructions
    "rules.md",       # Rule-based instructions
    "*.cursorrules"   # Cursor IDE format
  ]
  
  discover_with_patterns(root_path, patterns, :project)
end
```

### 5.4 Workspace-Level Instructions

IDE and workspace-specific instructions:

```elixir
defp discover_workspace_instructions(root_path) do
  patterns = [
    ".vscode/*.md",          # VS Code instructions
    ".vscode/instructions.md", # VS Code specific
    ".idea/*.md",            # IntelliJ IDEA instructions
    ".idea/instructions.md",   # IDEA specific
    "workspace.md",          # Workspace instructions
    ".workspace/*.md",       # Workspace directory
    ".rules/workspace.md"    # Workspace rules
  ]
  
  discover_with_patterns(root_path, patterns, :workspace)
end
```

### 5.5 Global Instructions

System-wide default instructions:

```elixir
defp discover_global_instructions do
  global_paths = [
    Path.expand("~/.config/claude/instructions.md"),
    Path.expand("~/.config/rubberduck/AGENTS.md"),
    Path.expand("~/.agents.md"),
    Path.expand("~/.cursorrules"),
    "/etc/claude/instructions.md",
    "/etc/rubberduck/AGENTS.md"
  ]
  
  existing_files = 
    global_paths
    |> Enum.filter(&File.exists?/1)
    |> Enum.map(&{&1, :global})
  
  {:ok, existing_files}
end
```

### 5.6 Conflict Resolution

When multiple files provide instructions for the same context:

```elixir
defp resolve_conflicts(parsed_files, auto_resolve) do
  grouped = Enum.group_by(parsed_files, & &1.context_key)
  
  {resolved_files, conflicts} = 
    grouped
    |> Enum.reduce({[], []}, fn {context_key, files}, {resolved_acc, conflict_acc} ->
      case length(files) do
        1 -> 
          {[hd(files) | resolved_acc], conflict_acc}
        _ -> 
          {winner, losers} = resolve_conflict_automatically(files)
          conflict = create_conflict_record(context_key, winner, losers)
          {[winner | resolved_acc], [conflict | conflict_acc]}
      end
    end)
  
  {:ok, resolved_files, conflicts}
end

defp resolve_conflict_automatically(files) do
  # Sort by priority (highest first), then by modification time (newest first)
  sorted_files = 
    files
    |> Enum.sort_by(fn file ->
      {-file.priority, -DateTime.to_unix(file.modified_at)}
    end)
  
  [winner | losers] = sorted_files
  {winner, losers}
end
```

## 6. Template Processing {#template-processing}

### 6.1 Liquid Template Engine

The TemplateProcessor uses Solid (Liquid) for secure template processing:

```elixir
defmodule RubberDuck.Instructions.TemplateProcessor do
  def process_template(template_content, variables \\ %{}, opts \\ []) do
    with {:ok, processed_template} <- maybe_process_inheritance(template_content),
         {:ok, validated_template} <- maybe_validate_template(processed_template),
         {:ok, sanitized_vars} <- sanitize_variables(variables),
         {:ok, rendered} <- render_template(validated_template, sanitized_vars),
         {:ok, final_output} <- maybe_convert_markdown(rendered) do
      {:ok, final_output}
    end
  end
  
  defp render_solid_template(template_content, variables) do
    with {:ok, template} <- Solid.parse(template_content),
         {:ok, rendered, _warnings} <- Solid.render(template, variables) do
      {:ok, to_string(rendered)}
    else
      {:error, error} -> {:error, {:template_error, error}}
    end
  end
end
```

### 6.2 Variable Substitution

Templates support variable substitution for dynamic content:

```liquid
# Project: {{ project_name }}

Instructions for {{ project_name }} development.

## Environment
- Current environment: {{ env }}
- Timestamp: {{ timestamp }}
- Date: {{ date }}

## User Context
{% if user_role == "admin" %}
Admin-specific instructions here.
{% elsif user_role == "developer" %}
Developer-specific instructions here.
{% endif %}

## Conditional Logic
{% if feature_flags.new_ui %}
Use the new UI components from /components/v2/
{% else %}
Use legacy components from /components/v1/
{% endif %}
```

### 6.3 Template Inheritance

Support for template composition and inheritance:

```liquid
{% extends "base_instructions.md" %}

{% block project_specific %}
## Project-Specific Rules
- Use TypeScript for all new files
- Follow the established folder structure
- Include unit tests for all functions
{% endblock %}

{% block code_style %}
{{ super }}
- Additional project-specific style rules
- Use Prettier for formatting
{% endblock %}
```

### 6.4 Standard Context Variables

Built-in variables available to all templates:

```elixir
def build_standard_context(custom_vars \\ %{}) do
  %{
    "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
    "date" => Date.utc_today() |> Date.to_iso8601(),
    "env" => Mix.env() |> to_string(),
    
    # Safe string functions
    "upcase" => &String.upcase/1,
    "downcase" => &String.downcase/1,
    "trim" => &String.trim/1,
    "length" => &String.length/1,
    
    # Safe list functions
    "join" => &Enum.join/2,
    "count" => &Enum.count/1,
    
    # Safe date/time functions
    "now" => fn -> DateTime.utc_now() |> DateTime.to_iso8601() end,
    "today" => fn -> Date.utc_today() |> Date.to_iso8601() end
  }
  |> Map.merge(stringify_keys(custom_vars))
end
```

## 7. Security Features {#security-features}

### 7.1 Comprehensive Validation

The Security module provides multi-layered validation:

```elixir
defmodule RubberDuck.Instructions.Security do
  def validate_template(template, opts \\ []) do
    with :ok <- check_template_size(template),
         :ok <- check_dangerous_patterns(template),
         :ok <- check_complexity(template, opts),
         :ok <- check_variable_names(template),
         :ok <- check_advanced_patterns(template) do
      :ok
    end
  end
  
  def validate_template_advanced(template, opts \\ []) do
    with :ok <- validate_template(template, opts),
         :ok <- analyze_template_ast(template),
         :ok <- check_template_entropy(template) do
      :ok
    end
  end
end
```

### 7.2 Injection Prevention

Detects and prevents various injection attempts:

```elixir
defp check_dangerous_patterns(template) do
  dangerous_patterns = [
    # System access
    ~r/\bSystem\./,
    ~r/\bFile\./,
    ~r/\bIO\./,
    ~r/\bCode\./,
    
    # Code execution
    ~r/\beval\b/i,
    ~r/\bexec\b/i,
    ~r/\bspawn\b/i,
    
    # Network access
    ~r/\b(HTTPoison|Tesla|Req)\b/,
    
    # Process manipulation
    ~r/GenServer\./,
    ~r/Task\./,
    ~r/Agent\./
  ]
  
  if Enum.any?(dangerous_patterns, &Regex.match?(&1, template)) do
    {:error, SecurityError.exception(reason: :injection_attempt)}
  else
    :ok
  end
end
```

### 7.3 Sandboxed Execution

Templates execute in a secure sandbox environment:

```elixir
def sandbox_context(variables) do
  %{
    # Only allow safe string functions
    "upcase" => &String.upcase/1,
    "downcase" => &String.downcase/1,
    "trim" => &String.trim/1,
    "length" => &String.length/1,
    
    # Safe list functions
    "join" => &Enum.join/2,
    "count" => &Enum.count/1,
    
    # Safe date/time functions
    "now" => fn -> DateTime.utc_now() |> DateTime.to_iso8601() end,
    "today" => fn -> Date.utc_today() |> Date.to_iso8601() end
  }
  |> Map.merge(variables)
end
```

### 7.4 Path Validation

Prevents path traversal attacks:

```elixir
def validate_path(path, allowed_root) do
  normalized_path = Path.expand(path)
  normalized_root = Path.expand(allowed_root)

  if String.starts_with?(normalized_path, normalized_root) do
    :ok
  else
    {:error, SecurityError.exception(reason: :path_traversal)}
  end
end

def validate_include_path(path) do
  cond do
    String.contains?(path, "..") ->
      {:error, SecurityError.exception(reason: :path_traversal)}
    String.contains?(path, "~") ->
      {:error, SecurityError.exception(reason: :path_traversal)}
    String.starts_with?(path, "/") ->
      {:error, SecurityError.exception(reason: :unauthorized_access)}
    true ->
      :ok
  end
end
```

### 7.5 Entropy Analysis

Detects obfuscated or encoded content:

```elixir
defp check_template_entropy(template) do
  if String.length(template) < 100 do
    :ok
  else
    entropy = calculate_shannon_entropy(template)
    
    # High entropy might indicate encoded/obfuscated content
    if entropy > 4.5 do
      {:error, SecurityError.exception(reason: :suspicious_content)}
    else
      :ok
    end
  end
end

defp calculate_shannon_entropy(string) do
  chars = String.graphemes(string)
  total = length(chars)
  
  if total == 0 do
    0.0
  else
    char_counts = Enum.frequencies(chars)
    
    char_counts
    |> Map.values()
    |> Enum.reduce(0.0, fn count, entropy ->
      probability = count / total
      entropy - (probability * :math.log2(probability))
    end)
  end
end
```

## 8. Configuration {#configuration}

### 8.1 System Configuration

Configure the instructions system in `config/config.exs`:

```elixir
# Instructions system configuration
config :rubber_duck, :instructions,
  default_rules_directory: ".rules",
  discovery_priority: [".rules", "instructions", ".instructions"],
  max_file_size: 25_000,
  max_depth: 10,
  max_files_per_directory: 50,
  include_global: true,
  follow_symlinks: false,
  cache_enabled: true,
  cache_ttl: 300_000  # 5 minutes
```

### 8.2 Runtime Configuration

Configure instruction loading at runtime:

```elixir
# Load instructions with custom options
{:ok, result} = HierarchicalLoader.load_instructions("/path/to/project", [
  include_global: false,
  auto_resolve_conflicts: true,
  validate_content: true,
  register_instructions: true,
  dry_run: false
])
```

### 8.3 Environment Variables

Override configuration with environment variables:

```bash
# Override default configuration
export RUBBER_DUCK_INSTRUCTIONS_MAX_FILE_SIZE=50000
export RUBBER_DUCK_INSTRUCTIONS_INCLUDE_GLOBAL=false
export RUBBER_DUCK_INSTRUCTIONS_DEFAULT_RULES_DIR=".instructions"
```

### 8.4 Per-Project Configuration

Configure instructions per project in `.rubberduck.config`:

```yaml
instructions:
  discovery_paths:
    - ".rules"
    - "docs/instructions"
    - ".config/ai"
  
  file_patterns:
    - "*.md"
    - "*.mdc"
    - "AGENTS.md"
  
  security:
    max_file_size: 30000
    validate_templates: true
    
  processing:
    enable_templating: true
    enable_inheritance: true
```

## 9. Metadata and Frontmatter {#metadata-frontmatter}

### 9.1 YAML Frontmatter

Instructions support rich metadata through YAML frontmatter:

```yaml
---
# Basic metadata
title: "Project Instructions"
description: "Core development guidelines"
version: "1.2.0"
author: "Development Team"
created: "2024-01-15"
modified: "2024-03-20"

# Priority and type
priority: high        # low, normal, high, critical
type: auto           # always, auto, agent, manual

# Categorization
tags: [elixir, phoenix, testing, documentation]
category: development
context: project

# Conditional application
applies_to:
  - environment: [development, staging]
  - file_types: [".ex", ".exs"]
  - directories: ["lib/", "test/"]

# Template configuration
template:
  engine: liquid
  variables:
    project_name: "RubberDuck"
    team: "AI Development"
    
# Inheritance
extends: "base_instructions.md"
includes:
  - "code_style.md"
  - "testing_guidelines.md"
---

# Instruction Content Here
```

### 9.2 Metadata Validation

The system validates metadata for correctness:

```elixir
defp validate_metadata(metadata) do
  base_metadata = %{
    "priority" => "normal",
    "type" => "auto", 
    "tags" => []
  }
  
  metadata
  |> Map.merge(base_metadata, fn _key, new_val, _default -> new_val end)
  |> Map.update("priority", "normal", &validate_priority/1)
  |> Map.update("type", "auto", &validate_rule_type/1)
  |> Map.update("tags", [], &validate_tags/1)
end

defp validate_priority(priority) when priority in ["low", "normal", "high", "critical"], do: priority
defp validate_priority(_), do: "normal"

defp validate_rule_type(type) when type in ["always", "auto", "agent", "manual"], do: type
defp validate_rule_type(_), do: "auto"

defp validate_tags(tags) when is_list(tags) do
  tags
  |> Enum.filter(&is_binary/1)
  |> Enum.take(10)
end
defp validate_tags(_), do: []
```

### 9.3 Metadata Usage

Metadata influences instruction processing:

```elixir
# Priority affects loading order
defp determine_priority(metadata, file_path) do
  base_priority = calculate_base_priority(file_path)
  
  metadata_priority = case Map.get(metadata, "priority", "normal") do
    "critical" -> 200
    "high" -> 100
    "normal" -> 0
    "low" -> -100
    _ -> 0
  end
  
  base_priority + metadata_priority
end

# Type affects when instructions are applied
defp determine_instruction_type(metadata, _file_path) do
  case Map.get(metadata, "type", "auto") do
    type when type in ["always", "auto", "agent", "manual"] ->
      String.to_atom(type)
    _ -> 
      :auto
  end
end
```

## 10. Usage Examples {#usage-examples}

### 10.1 Basic Project Instructions

Simple project-level instructions in `AGENTS.md`:

```markdown
---
priority: high
type: always
tags: [elixir, phoenix, project]
---

# RubberDuck Project Instructions

## Development Guidelines

- Use Elixir 1.15+ and Phoenix 1.7+
- Follow the Ash Framework patterns
- Write comprehensive tests
- Document all public APIs

## Code Style

- Use snake_case for variables and functions
- Use PascalCase for modules
- Prefer pattern matching over conditionals
- Use `with` for error handling chains

## Testing

- Unit tests in `test/` directory
- Integration tests in `test/integration/`
- Use ExUnit for testing
- Aim for 90%+ code coverage
```

### 10.2 Templated Instructions

Dynamic instructions with variables in `.rules/development.md`:

```markdown
---
priority: critical
type: auto
tags: [development, templating]
context: development
---

# {{ project_name }} Development Rules

Current environment: **{{ env }}**
Last updated: {{ timestamp }}

## Project Structure

```
{{ project_name }}/
├── lib/
│   └── {{ project_name | downcase }}/
├── test/
└── config/
```

## Environment-Specific Rules

{% if env == "development" %}
### Development Environment
- Enable debug logging
- Use live reload for assets
- Connect to local database
{% elsif env == "production" %}
### Production Environment
- Minimize logging
- Enable caching
- Use SSL connections
{% endif %}

## User-Specific Instructions

{% if user_role == "admin" %}
### Administrator Access
- Full system access
- Can modify core configurations
- Access to production logs
{% elsif user_role == "developer" %}
### Developer Access
- Limited to development environment
- Can run tests and start server
- Access to development logs
{% endif %}
```

### 10.3 Cursor IDE Integration

Cursor-specific rules in `.cursorrules`:

```
# Cursor IDE Rules for RubberDuck

## File Types
- .ex files: Elixir modules
- .exs files: Elixir scripts
- .heex files: Phoenix templates
- .js files: JavaScript
- .css files: Stylesheets

## Code Generation
- Generate Elixir modules with proper documentation
- Include @moduledoc and @doc for all public functions
- Follow Elixir naming conventions
- Add typespecs for all public functions

## Testing
- Generate ExUnit test cases
- Include setup and teardown when needed
- Use descriptive test names
- Test both success and error cases

## Phoenix Specific
- Generate LiveView components with proper lifecycle
- Include CSS classes for styling
- Use Phoenix.HTML helpers for forms
- Follow Phoenix routing conventions
```

### 10.4 Workspace-Specific Instructions

VS Code workspace instructions in `.vscode/instructions.md`:

```markdown
---
priority: normal
type: agent
tags: [vscode, workspace, debugging]
---

# VS Code Workspace Instructions

## Debugging Configuration

Use the following launch configuration for debugging:

```json
{
  "type": "elixir",
  "request": "launch",
  "name": "mix test",
  "task": "test",
  "taskArgs": ["--trace"],
  "requireFiles": ["test/test_helper.exs"]
}
```

## Extensions

Recommended extensions for this project:
- ElixirLS
- Phoenix Framework
- Elixir Test
- GitLens

## Workspace Settings

```json
{
  "elixir.autoBuild": true,
  "elixir.dialyzer.enabled": true,
  "editor.formatOnSave": true
}
```
```

### 10.5 Conditional Instructions

Instructions with conditional logic in `.rules/conditional.md`:

```markdown
---
priority: high
type: auto
tags: [conditional, feature-flags]
applies_to:
  environment: [development, staging]
  file_types: [".ex", ".exs"]
---

# Conditional Development Instructions

## Feature Flags

{% if feature_flags.new_auth_system %}
### New Authentication System
- Use the new Auth module from lib/rubber_duck/auth/
- Implement JWT token validation
- Follow OAuth 2.0 patterns
{% else %}
### Legacy Authentication
- Continue using the legacy auth system
- Maintain backward compatibility
- Plan migration to new system
{% endif %}

## Database Configuration

{% if database_type == "postgresql" %}
### PostgreSQL Configuration
- Use Ecto with PostgreSQL adapter
- Enable UUID primary keys
- Use JSONB for flexible data storage
{% elsif database_type == "mysql" %}
### MySQL Configuration
- Use Ecto with MySQL adapter
- Use BIGINT for primary keys
- Use JSON columns for flexible data
{% endif %}

## Environment-Specific Behavior

{% case env %}
{% when "development" %}
### Development Environment
- Enable query logging
- Use local file storage
- Disable email sending
{% when "staging" %}
### Staging Environment
- Enable error tracking
- Use cloud storage
- Send emails to test accounts
{% when "production" %}
### Production Environment
- Enable all monitoring
- Use distributed storage
- Send real emails
{% endcase %}
```

## 11. Best Practices {#best-practices}

### 11.1 File Organization

```
project/
├── .rules/                    # Highest priority rules
│   ├── development.md         # Development-specific
│   ├── testing.md            # Testing guidelines
│   └── deployment.md         # Deployment rules
├── AGENTS.md                 # Primary project instructions
├── .cursorrules              # Cursor IDE integration
├── .vscode/
│   └── instructions.md       # VS Code specific
└── docs/
    └── instructions/         # Documentation
        ├── api.md
        └── architecture.md
```

### 11.2 Writing Effective Instructions

**Be Specific and Actionable**
```markdown
# Good: Specific instruction
- Use `GenServer.call/3` with 30-second timeout for external API calls
- Handle {:error, :timeout} with exponential backoff

# Bad: Vague instruction
- Handle timeouts properly
- Use good error handling
```

**Use Clear Hierarchies**
```markdown
# Primary Rule
## Sub-category
### Specific Implementation
- Concrete action item
- Another action item

#### Edge Cases
- Handle when X happens
- Handle when Y happens
```

**Include Examples**
```markdown
## Pattern Matching Guidelines

Prefer pattern matching over conditionals:

```elixir
# Good
def process_result({:ok, data}), do: handle_success(data)
def process_result({:error, reason}), do: handle_error(reason)

# Avoid
def process_result(result) do
  if elem(result, 0) == :ok do
    handle_success(elem(result, 1))
  else
    handle_error(elem(result, 1))
  end
end
```

### 11.3 Metadata Best Practices

**Use Appropriate Priorities**
```yaml
---
priority: critical  # Core project rules, security requirements
priority: high      # Important coding standards, testing requirements
priority: normal    # General guidelines, preferences
priority: low       # Suggestions, nice-to-haves
---
```

**Tag Consistently**
```yaml
---
tags: [elixir, phoenix, testing, security]  # Descriptive, consistent
tags: [backend, frontend, mobile]           # Platform-specific
tags: [development, staging, production]    # Environment-specific
---
```

**Use Conditional Logic Wisely**
```markdown
{% if user_experience == "beginner" %}
## Beginner Guidelines
- Start with simple examples
- Explain all concepts thoroughly
- Provide step-by-step instructions
{% elsif user_experience == "expert" %}
## Expert Guidelines
- Focus on advanced patterns
- Assume knowledge of fundamentals
- Provide optimization tips
{% endif %}
```

### 11.4 Template Best Practices

**Keep Templates Simple**
```liquid
<!-- Good: Simple variable substitution -->
# Welcome to {{ project_name }}

<!-- Good: Simple conditional -->
{% if debug_mode %}
Debug mode is enabled.
{% endif %}

<!-- Avoid: Complex nested logic -->
{% for item in items %}
  {% if item.enabled %}
    {% case item.type %}
      {% when "important" %}
        <!-- Complex nested structure -->
      {% when "normal" %}
        <!-- More complex logic -->
    {% endcase %}
  {% endif %}
{% endfor %}
```

**Use Descriptive Variable Names**
```liquid
<!-- Good: Clear variable names -->
Environment: {{ current_environment }}
Project: {{ project_name }}
User: {{ user_display_name }}

<!-- Bad: Unclear variables -->
Env: {{ env }}
Proj: {{ proj }}
U: {{ u }}
```

### 11.5 Security Best Practices

**Validate All User Input**
```elixir
# Always validate template variables
def build_context(user_input) do
  %{
    "project_name" => sanitize_string(user_input.project_name),
    "user_role" => validate_role(user_input.role),
    "env" => validate_environment(user_input.environment)
  }
end
```

**Use Whitelist Approach**
```elixir
# Define allowed values explicitly
def validate_environment(env) when env in ["development", "staging", "production"], do: env
def validate_environment(_), do: "development"

def validate_role(role) when role in ["admin", "developer", "viewer"], do: role
def validate_role(_), do: "viewer"
```

**Avoid Dynamic Code Generation**
```markdown
<!-- Good: Static instruction -->
Use the following pattern for GenServers:

```elixir
defmodule MyApp.Worker do
  use GenServer
  # ... implementation
end
```

<!-- Bad: Dynamic code generation -->
{% assign module_name = user_input.module_name %}
Use this pattern:

```elixir
defmodule {{ module_name }} do
  # This could be dangerous!
end
```

### 11.6 Performance Best Practices

**Minimize Template Complexity**
- Keep templates under 1000 lines
- Avoid deep nesting (max 3 levels)
- Use includes for shared content
- Cache frequently used templates

**Optimize File Discovery**
```elixir
# Good: Specific patterns
patterns = [
  ".rules/*.md",
  "AGENTS.md",
  "instructions.md"
]

# Bad: Overly broad patterns
patterns = [
  "**/*.md",
  "**/*.txt",
  "**/instructions*"
]
```

**Use Appropriate Caching**
```elixir
# Cache processed templates
@cache_timeout 300_000  # 5 minutes

def get_processed_template(file_path, variables) do
  cache_key = generate_cache_key(file_path, variables)
  
  case :ets.lookup(@cache_table, cache_key) do
    [{^cache_key, result, expiry}] when expiry > now() ->
      result
    _ ->
      result = process_template(file_path, variables)
      :ets.insert(@cache_table, {cache_key, result, now() + @cache_timeout})
      result
  end
end
```

## 12. API Reference {#api-reference}

### 12.1 FileManager

Core file discovery and management:

```elixir
defmodule RubberDuck.Instructions.FileManager do
  @doc "Discovers instruction files in the given directory"
  @spec discover_files(String.t(), keyword()) :: {:ok, [instruction_file()]} | {:error, term()}
  def discover_files(path \\ ".", opts \\ [])
  
  @doc "Loads and processes an instruction file"
  @spec load_file(String.t(), map()) :: {:ok, instruction_file()} | {:error, term()}
  def load_file(file_path, variables \\ %{})
  
  @doc "Validates an instruction file"
  @spec validate_file(String.t()) :: {:ok, map()} | {:error, term()}
  def validate_file(file_path)
  
  @doc "Returns file statistics"
  @spec get_file_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def get_file_stats(root_path)
end
```

### 12.2 HierarchicalLoader

Orchestrates hierarchical loading:

```elixir
defmodule RubberDuck.Instructions.HierarchicalLoader do
  @doc "Loads instructions hierarchically"
  @spec load_instructions(String.t(), keyword()) :: {:ok, loading_result()} | {:error, term()}
  def load_instructions(root_path \\ ".", opts \\ [])
  
  @doc "Discovers instructions at a specific level"
  @spec discover_at_level(String.t(), atom()) :: {:ok, [String.t()]} | {:error, term()}
  def discover_at_level(root_path, level)
  
  @doc "Analyzes instruction hierarchy without loading"
  @spec analyze_hierarchy(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_hierarchy(root_path, opts \\ [])
end
```

### 12.3 TemplateProcessor

Handles template processing and rendering:

```elixir
defmodule RubberDuck.Instructions.TemplateProcessor do
  @doc "Processes a template through the security pipeline"
  @spec process_template_secure(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def process_template_secure(template_content, variables \\ %{}, opts \\ [])
  
  @doc "Processes a template with variables"
  @spec process_template(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def process_template(template_content, variables \\ %{}, opts \\ [])
  
  @doc "Validates a template without rendering"
  @spec validate_template(String.t(), atom()) :: {:ok, term()} | {:error, term()}
  def validate_template(template_content, type \\ :user)
  
  @doc "Extracts metadata from template frontmatter"
  @spec extract_metadata(String.t()) :: {:ok, map(), String.t()} | {:error, term()}
  def extract_metadata(template_content)
  
  @doc "Builds standard context variables"
  @spec build_standard_context(map()) :: map()
  def build_standard_context(custom_vars \\ %{})
end
```

### 12.4 Security

Provides security validation and sandboxing:

```elixir
defmodule RubberDuck.Instructions.Security do
  @doc "Validates a template for security concerns"
  @spec validate_template(String.t(), keyword()) :: :ok | {:error, term()}
  def validate_template(template, opts \\ [])
  
  @doc "Performs advanced security validation"
  @spec validate_template_advanced(String.t(), keyword()) :: :ok | {:error, term()}
  def validate_template_advanced(template, opts \\ [])
  
  @doc "Validates variables before processing"
  @spec validate_variables(map()) :: :ok | {:error, term()}
  def validate_variables(variables)
  
  @doc "Validates a file path for security"
  @spec validate_path(String.t(), String.t()) :: :ok | {:error, term()}
  def validate_path(path, allowed_root)
  
  @doc "Creates a sandbox context for template execution"
  @spec sandbox_context(map()) :: map()
  def sandbox_context(variables)
end
```

### 12.5 Common Types

```elixir
@type instruction_file :: %{
  path: String.t(),
  type: instruction_type(),
  priority: integer(),
  scope: scope_level(),
  metadata: map(),
  content: String.t(),
  size: integer(),
  modified_at: DateTime.t()
}

@type instruction_type :: :always | :auto | :agent | :manual
@type scope_level :: :directory | :project | :workspace | :global

@type loading_result :: %{
  loaded: [loaded_instruction()],
  skipped: [skipped_instruction()],
  errors: [failed_instruction()],
  conflicts: [conflict_resolution()],
  stats: loading_stats()
}
```

## 13. Troubleshooting {#troubleshooting}

### 13.1 Common Issues

**Files Not Being Discovered**
```elixir
# Check file patterns
{:ok, files} = FileManager.discover_files(".", include_global: true)
IO.inspect(files, label: "Discovered files")

# Enable debug logging
Logger.configure(level: :debug)
```

**Template Processing Errors**
```elixir
# Validate template syntax
case TemplateProcessor.validate_template(template_content) do
  {:ok, _} -> IO.puts("Template is valid")
  {:error, reason} -> IO.puts("Template error: #{inspect(reason)}")
end

# Check variable validation
case Security.validate_variables(variables) do
  :ok -> IO.puts("Variables are safe")
  {:error, reason} -> IO.puts("Variable error: #{inspect(reason)}")
end
```

**Security Validation Failures**
```elixir
# Check for dangerous patterns
case Security.validate_template(template_content) do
  :ok -> IO.puts("Template passed security checks")
  {:error, %SecurityError{reason: reason}} -> 
    IO.puts("Security error: #{reason}")
end

# Use advanced validation for detailed analysis
case Security.validate_template_advanced(template_content) do
  :ok -> IO.puts("Template passed advanced security checks")
  {:error, reason} -> IO.puts("Advanced security error: #{inspect(reason)}")
end
```

### 13.2 Debug Tools

**Hierarchical Analysis**
```elixir
# Analyze instruction hierarchy
{:ok, analysis} = HierarchicalLoader.analyze_hierarchy("/path/to/project")

IO.inspect(analysis.hierarchy_levels, label: "Hierarchy levels")
IO.inspect(analysis.conflict_analysis, label: "Conflicts")
IO.inspect(analysis.recommendations, label: "Recommendations")
```

**Template Debugging**
```elixir
# Debug template processing
defmodule TemplateDebugger do
  def debug_template(template_content, variables) do
    IO.puts("=== Template Debug ===")
    IO.puts("Template content:")
    IO.puts(template_content)
    
    IO.puts("\nVariables:")
    IO.inspect(variables)
    
    case TemplateProcessor.process_template(template_content, variables) do
      {:ok, result} ->
        IO.puts("\nProcessed result:")
        IO.puts(result)
        
      {:error, reason} ->
        IO.puts("\nProcessing error:")
        IO.inspect(reason)
    end
  end
end
```

**Performance Monitoring**
```elixir
# Monitor instruction loading performance
:telemetry.attach("instruction-loading", 
  [:instructions, :loading, :complete], 
  fn event, measurements, metadata, _config ->
    IO.puts("Instruction loading took #{measurements.duration}ms")
    IO.puts("Loaded #{metadata.file_count} files")
  end,
  nil
)
```

### 13.3 Configuration Issues

**Check Configuration**
```elixir
# Inspect current configuration
config = Application.get_env(:rubber_duck, :instructions)
IO.inspect(config, label: "Instructions configuration")

# Validate configuration
case validate_configuration(config) do
  :ok -> IO.puts("Configuration is valid")
  {:error, reason} -> IO.puts("Configuration error: #{reason}")
end
```

**Reset Configuration**
```elixir
# Reset to default configuration
Application.put_env(:rubber_duck, :instructions, [
  default_rules_directory: ".rules",
  discovery_priority: [".rules", "instructions", ".instructions"],
  max_file_size: 25_000,
  include_global: true
])
```

### 13.4 Testing Instructions

**Unit Tests**
```elixir
defmodule InstructionTest do
  use ExUnit.Case
  
  test "discovers project instructions" do
    {:ok, files} = FileManager.discover_files("test/fixtures/project")
    
    assert length(files) > 0
    assert Enum.any?(files, &String.ends_with?(&1.path, "AGENTS.md"))
  end
  
  test "processes template with variables" do
    template = "Hello {{ name }}"
    variables = %{"name" => "World"}
    
    {:ok, result} = TemplateProcessor.process_template(template, variables)
    assert result =~ "Hello World"
  end
  
  test "validates dangerous templates" do
    dangerous_template = "{{ System.cmd('rm', ['-rf', '/']) }}"
    
    assert {:error, _} = Security.validate_template(dangerous_template)
  end
end
```

**Integration Tests**
```elixir
defmodule InstructionIntegrationTest do
  use ExUnit.Case
  
  test "full instruction loading pipeline" do
    # Create test files
    setup_test_files()
    
    # Load instructions
    {:ok, result} = HierarchicalLoader.load_instructions("test/fixtures")
    
    # Verify results
    assert length(result.loaded) > 0
    assert result.stats.total_errors == 0
    
    # Cleanup
    cleanup_test_files()
  end
end
```

## Conclusion

The RubberDuck Instructions System provides a comprehensive, secure, and flexible foundation for managing AI assistant instructions across different contexts and scopes. By leveraging hierarchical discovery, template processing, and robust security features, the system ensures that instructions are automatically discovered, safely processed, and intelligently applied.

Key takeaways:
- Use the hierarchical file structure for appropriate instruction scoping
- Leverage YAML frontmatter for rich metadata and conditional logic
- Apply security best practices to prevent injection attacks
- Utilize templating for dynamic, context-aware instructions
- Monitor and optimize based on usage patterns and performance metrics

The system's modular architecture ensures that new features and file formats can be easily integrated as requirements evolve, while maintaining backward compatibility and security standards.