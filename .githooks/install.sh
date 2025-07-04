#!/bin/bash
# Script to install git hooks for RubberDuck project

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🦆 Installing RubberDuck Git Hooks..."

# Get the project root directory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$PROJECT_ROOT" ]; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

cd "$PROJECT_ROOT"

# Check if .githooks directory exists
if [ ! -d ".githooks" ]; then
    echo -e "${RED}Error: .githooks directory not found${NC}"
    exit 1
fi

# Configure git to use the .githooks directory
echo "Configuring git to use .githooks directory..."
git config core.hooksPath .githooks

# Make all hooks executable
echo "Making hooks executable..."
find .githooks -type f -name "*" -not -name "*.sh" -not -name "README.md" -exec chmod +x {} \;

# Verify installation
HOOKS_PATH=$(git config core.hooksPath)
if [ "$HOOKS_PATH" = ".githooks" ]; then
    echo -e "${GREEN}✅ Git hooks installed successfully!${NC}"
    echo ""
    echo "Available hooks:"
    for hook in .githooks/*; do
        if [ -f "$hook" ] && [ -x "$hook" ] && [[ ! "$hook" =~ \.(sh|md)$ ]]; then
            echo "  - $(basename "$hook")"
        fi
    done
    echo ""
    echo -e "${YELLOW}Note: To uninstall hooks, run:${NC}"
    echo "  git config --unset core.hooksPath"
else
    echo -e "${RED}❌ Failed to install git hooks${NC}"
    exit 1
fi