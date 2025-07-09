#!/bin/bash
# RubberDuck Setup Script

set -e

echo "🦆 RubberDuck Setup Script"
echo "========================="
echo

# Check prerequisites
echo "Checking prerequisites..."

# Check Elixir
if ! command -v elixir &> /dev/null; then
    echo "❌ Elixir not found. Please install Elixir 1.15+"
    exit 1
fi

# Check PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "❌ PostgreSQL not found. Please install PostgreSQL 16+"
    exit 1
fi

echo "✅ Prerequisites satisfied"
echo

# Install dependencies
echo "Installing dependencies..."
mix deps.get
echo "✅ Dependencies installed"
echo

# Setup database
echo "Setting up database..."
echo "This will create the database and run migrations."
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mix ash.setup
    echo "✅ Database setup complete"
else
    echo "⏭️  Skipping database setup"
fi
echo

# Compile project
echo "Compiling project..."
mix compile
echo "✅ Project compiled"
echo

# Optional: Build escript
read -p "Build CLI executable? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mix escript.build
    echo "✅ CLI executable built at ./rubber_duck"
    echo
    echo "You can now run: ./rubber_duck <command>"
else
    echo "You can run the CLI with: mix rubber_duck <command>"
fi
echo

echo "🎉 Setup complete!"
echo
echo "Next steps:"
echo "1. Start an LLM service (e.g., 'ollama serve')"
echo "2. Connect RubberDuck to the LLM: 'mix rubber_duck llm connect ollama'"
echo "3. Try a command: 'mix rubber_duck generate \"hello world function\"'"
echo
echo "For more information, see guides/user/001-command_line_interface.md"