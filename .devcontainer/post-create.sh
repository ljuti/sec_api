#!/bin/bash
set -e

echo "Running post-create setup..."

# Install Claude Code CLI
echo "Installing Claude Code CLI..."
curl -fsSL https://claude.ai/install.sh | bash

# Install gem dependencies
echo "Installing bundle dependencies..."
bundle install

# Install any additional global gems needed for development
echo "Installing additional development gems..."
gem install bundler-audit

# Set up git hooks if needed (uncomment if you want to use them)
# echo "Setting up git hooks..."
# bundle exec overcommit --install

# Create any necessary directories
echo "Creating necessary directories..."
mkdir -p tmp
mkdir -p log

# Generate YARD documentation
echo "Generating YARD documentation..."
bundle exec yard doc --no-progress || true

# Run initial test suite to ensure everything works
echo "Running initial test suite..."
bundle exec rspec --fail-fast || echo "Warning: Some tests failed. You may want to investigate."

# Display useful information
echo ""
echo "========================================="
echo "Post-create setup complete!"
echo "========================================="
echo ""
echo "Available commands:"
echo "  bundle exec rspec       - Run tests"
echo "  bundle exec standardrb  - Run linter"
echo "  bin/console            - Interactive console"
echo "  bundle exec rake       - Run default task"
echo "  claude                 - Claude Code CLI"
echo ""
echo "Ruby version: $(ruby -v)"
echo "Bundler version: $(bundle -v)"
echo "Claude Code: $(claude --version 2>/dev/null || echo 'not found in PATH yet - restart terminal')"
echo ""
