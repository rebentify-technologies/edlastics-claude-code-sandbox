FROM node:22

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -a 'alias es-claude="claude --plugin-dir /workspace/dev-local/ai-knowledgebase --dangerously-skip-permissions"' \
  -a 'alias gcloud-login="pnpm dlx google-artifactregistry-auth"' \
  -a '[ -n "$GCP_SERVICE_ACCOUNT_KEY_BASE64" ] && { [ -f ~/.gcp-key.json ] || { echo "$GCP_SERVICE_ACCOUNT_KEY_BASE64" | base64 -d > ~/.gcp-key.json && chmod 600 ~/.gcp-key.json; }; export GOOGLE_APPLICATION_CREDENTIALS=~/.gcp-key.json; }' \
  -a '[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] && pnpm dlx google-artifactregistry-auth >/dev/null 2>&1' \
  -x

# Trust every repo under /workspace regardless of filesystem ownership quirks
# (devcontainer bind-mounts from Windows/WSL can trip git's "dubious ownership"
# check even though the files are functionally ours). Also wire gh up as the
# credential helper so `git` over HTTPS transparently uses $GH_TOKEN — without
# this, `git fetch`/`git push` prompt for a username even when `gh auth status`
# reports logged in.
RUN git config --global --add safe.directory '*' \
  && gh auth setup-git

# Install .NET 10 SDK (user-local)
RUN wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh && \
  chmod +x /tmp/dotnet-install.sh && \
  /tmp/dotnet-install.sh --channel 10.0 --install-dir $HOME/.dotnet && \
  rm /tmp/dotnet-install.sh

ENV DOTNET_ROOT=/home/${USERNAME}/.dotnet
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=true
ENV PATH=$PATH:/home/${USERNAME}/.dotnet:/home/${USERNAME}/.dotnet/tools

# Install Claude, google-artifactregistry-auth (preinstall hook uses it to
# fetch an Artifact Registry token into ~/.npmrc), and enable Corepack so
# pnpm is available out of the box. Repos pin their pnpm version via
# `"packageManager": "pnpm@<version>"`; Corepack downloads that exact
# version on first invocation.
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} google-artifactregistry-auth \
  && corepack enable --install-directory /usr/local/share/npm-global/bin

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
