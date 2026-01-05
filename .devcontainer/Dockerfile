# Use official Ruby image as base
ARG RUBY_VERSION=3.1
FROM ruby:${RUBY_VERSION}

# Install system dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    build-essential \
    git \
    curl \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libffi-dev \
    libgdbm-dev \
    libncurses5-dev \
    libsqlite3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create vscode user with sudo access
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install bundler
RUN gem update --system && gem install bundler

# Set up workspace directory
WORKDIR /workspace

# Switch to non-root user
USER $USERNAME

# Set environment variables for Ruby
ENV GEM_HOME=/home/$USERNAME/.gem
ENV PATH=$GEM_HOME/bin:$PATH

# Install common Ruby development tools
RUN gem install solargraph \
    && gem install rubocop \
    && gem install standard \
    && gem install debug

# Default command
CMD ["/bin/bash"]
