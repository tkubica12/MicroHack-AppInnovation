## Dev Container Dockerfile
## Base: Official devcontainers .NET 8 image (includes common tooling, non-root "vscode" user)
FROM mcr.microsoft.com/devcontainers/dotnet:1-8.0-bookworm

# Allow normal .NET patch roll-forward (previously disabled causing 8.0.0 vs 8.0.x runtime mismatch)
ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_ROLL_FORWARD=LatestPatch \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    AZURE_CORE_ONLY_SHOW_ERRORS=1

USER root

# Install prerequisites & Azure CLI
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release jq unzip git bash-completion \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update \
    && apt-get install -y azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Azure Developer CLI (azd) - pinned to latest at build time.
RUN curl -fsSL https://aka.ms/install-azd.sh | bash

# Ensure latest Bicep CLI (azure-cli bundles a version; we explicitly upgrade)
RUN az bicep install --upgrade || true

# Add bash completion for az & azd if present
RUN echo "# Azure CLI completion" >> /etc/bash.bashrc \
    && echo "source /etc/bash_completion.d/azure-cli || true" >> /etc/bash.bashrc \
    && echo "# azd completion" >> /etc/bash.bashrc \
    && azd completion bash > /etc/bash_completion.d/azd || true

# Optional: Docker CLI (allow building images via host socket mount)
RUN apt-get update \
    && apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -f docker \
    && usermod -aG docker vscode

USER vscode
WORKDIR /workspaces/MicroHack-AppInnovation

# Cache restore for dotnet solution when dependencies rarely change (best effort; ignore failures)
COPY dotnet/*.sln dotnet/ ./dotnet/
RUN find ./dotnet -maxdepth 2 -name '*.csproj' -print0 | xargs -0 -I{} echo "Restoring {}" \
    && dotnet restore ./dotnet 2>/dev/null || true

# Final message
CMD ["sleep", "infinity"]
