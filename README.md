# RubberDuck

An Elixir OTP-based coding assistant umbrella project.

## Project Structure

This is an umbrella project containing four applications:

- **rubber_duck_core** - Core business logic
- **rubber_duck_web** - Phoenix/WebSocket communication layer
- **rubber_duck_engines** - Analysis engines for code assistance
- **rubber_duck_storage** - Data persistence layer

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding the appropriate apps to your list of dependencies in `mix.exs`.

## Development

To get started with development:

```bash
# Get dependencies
mix deps.get

# Compile all apps
mix compile

# Run tests
mix test

# Format code
mix format
```

## Applications

### rubber_duck_core
Contains the main RubberDuck module and core functionality.

### rubber_duck_web
Will contain Phoenix channels for real-time communication.

### rubber_duck_engines
Will contain various analysis engines for code assistance features.

### rubber_duck_storage
Will contain Ecto schemas and data persistence logic.

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/rubber_duck>.