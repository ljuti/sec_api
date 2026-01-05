#!/bin/bash
set -e

echo "Running post-start tasks..."

# Check for outdated gems
echo "Checking for outdated gems..."
bundle outdated --only-explicit || true

# Check for security vulnerabilities
echo "Checking for security vulnerabilities..."
bundle-audit check --update || echo "Warning: Security vulnerabilities found. Run 'bundle-audit check' for details."

# Verify git configuration
echo "Verifying git configuration..."
git config --get user.name > /dev/null || echo "Warning: Git user.name not set. Run 'git config --global user.name \"Your Name\"'"
git config --get user.email > /dev/null || echo "Warning: Git user.email not set. Run 'git config --global user.email \"you@example.com\"'"

# Check if API key is configured (if needed)
if [ -f "config/secapi.yml" ]; then
    echo "API configuration file found: config/secapi.yml"
elif [ -n "$SECAPI_API_KEY" ]; then
    echo "API key configured via environment variable"
else
    echo "Note: API key not configured. Set SECAPI_API_KEY environment variable if needed."
fi

# Update bundle if Gemfile.lock is stale (optional - uncomment if desired)
# if [ Gemfile -nt Gemfile.lock ]; then
#     echo "Gemfile is newer than Gemfile.lock, running bundle install..."
#     bundle install
# fi

# Display current branch and status
echo ""
echo "Git branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo "Git status:"
git status --short 2>/dev/null || echo "Not a git repository"

echo ""
echo "========================================="
echo "Development environment ready!"
echo "========================================="
echo ""
