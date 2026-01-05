# DevContainer Setup for sec_api

This directory contains the development container configuration for the sec_api Ruby gem.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop) or [Docker Engine](https://docs.docker.com/engine/install/)
- [Visual Studio Code](https://code.visualstudio.com/)
- [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) for VS Code

## Quick Start

1. Open this project in VS Code
2. When prompted, click "Reopen in Container" (or use Command Palette: `Dev Containers: Reopen in Container`)
3. Wait for the container to build and start (first time may take a few minutes)
4. The setup scripts will run automatically:
   - `post-create.sh` runs once when the container is first created
   - `post-start.sh` runs every time the container starts

## What's Included

### Base Environment
- Ruby 3.1 (configurable via RUBY_VERSION arg)
- Bundler (latest)
- Git
- Build tools and common system dependencies

### Development Tools
- Solargraph (Ruby language server)
- RuboCop (linter)
- Standard (Ruby style guide)
- Debug gem

### VS Code Extensions
- Ruby LSP (Shopify)
- Ruby extension pack
- EndWise (auto-close Ruby blocks)
- Solargraph

## Configuration

### Ruby Version

To change the Ruby version, edit `.devcontainer/Dockerfile` and `.devcontainer/docker-compose.yml`:

```dockerfile
ARG RUBY_VERSION=3.2  # Change to desired version
```

### Environment Variables

Add environment variables in `.devcontainer/docker-compose.yml`:

```yaml
environment:
  - SECAPI_API_KEY=your_key_here
  - SECAPI_BASE_URL=https://api.sec-api.io
```

**Note:** For sensitive values like API keys, consider using a `.env` file (not committed to git) and reference it in docker-compose.yml.

### Lifecycle Scripts

The devcontainer uses two lifecycle scripts:

**`.devcontainer/post-create.sh`** - Runs once when container is first created:
- Installs bundle dependencies
- Installs additional development gems (bundler-audit)
- Creates necessary directories
- Generates YARD documentation
- Runs initial test suite

**`.devcontainer/post-start.sh`** - Runs every time container starts:
- Checks for outdated gems
- Runs security vulnerability scan
- Verifies git configuration
- Checks API key configuration
- Shows current git branch and status

You can customize these scripts to add your own setup tasks. For example:

```bash
# In post-create.sh - one-time setup
gem install specific_dev_tool
bundle exec rake db:setup

# In post-start.sh - every container start
echo "Welcome back!"
bundle outdated --only-explicit
```

### Additional Services

To add services like PostgreSQL or Redis, add them to `docker-compose.yml`:

```yaml
services:
  app:
    # ... existing config ...
    depends_on:
      - postgres

  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  postgres-data:
```

## Common Tasks

Once inside the container, you can run all the usual development commands:

```bash
# Install dependencies
bin/setup

# Run tests
bundle exec rspec

# Run linter
bundle exec standardrb

# Auto-fix linting issues
bundle exec standardrb --fix

# Interactive console
bin/console

# Install gem locally
bundle exec rake install
```

## SSH Keys

Your SSH keys from `~/.ssh` are mounted read-only into the container, so git operations that require authentication will work seamlessly.

## Bash History

Bash history is persisted in a Docker volume, so your command history survives container rebuilds.

## Rebuilding the Container

If you make changes to the Dockerfile or devcontainer.json:

1. Open Command Palette (Cmd+Shift+P / Ctrl+Shift+P)
2. Run `Dev Containers: Rebuild Container`

## Troubleshooting

### Container won't start
- Check Docker Desktop is running
- Try rebuilding: `Dev Containers: Rebuild Container`
- Check Docker logs for errors

### Permission issues
- The container runs as `vscode` user (UID 1000)
- File ownership should match your host user

### Bundle install fails
- Ensure Docker has enough memory (4GB+ recommended)
- Try running `bundle install` manually after container starts

### VS Code extensions not working
- Try reloading the window: `Developer: Reload Window`
- Check extension installation in the container's Extensions panel

## Benefits of This Setup

1. **Consistent Environment**: Everyone uses the same Ruby version and dependencies
2. **Isolated**: No conflicts with other Ruby projects or system Ruby
3. **Reproducible**: Works the same on macOS, Linux, and Windows
4. **Fast Onboarding**: New developers can get started with one click
5. **No Local Ruby Required**: Don't need to manage rbenv, rvm, or system Ruby
