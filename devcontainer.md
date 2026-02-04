# 🧰 Local Development Environment (Dev Container)

This repository includes a `.devcontainer/` configuration to support **local development, testing, and troubleshooting** using a consistent Linux-based environment.

The dev container is **optional** and is **not used by Azure DevOps pipelines** unless explicitly configured.

## What the dev container is for

The dev container provides:

- A repeatable Ubuntu-based development environment
- PowerShell 7+ with required Az and Microsoft Graph modules
- Azure CLI for authentication and local testing
- Environment parity with the Azure DevOps hosted Ubuntu agent

This allows contributors to:

- Reproduce pipeline behaviour locally
- Debug authentication, RBAC, and Graph-related issues
- Validate script changes before committing to the repository

## What the dev container does *not* do

- It does **not** affect Azure DevOps pipeline execution
- It does **not** change agent configuration
- It does **not** provision or modify Azure resources
- It does **not** automatically run in CI/CD

Azure DevOps hosted agents **ignore** the `.devcontainer/` directory by default.

## Installation metadata

The expected development environment is documented in:

```
.devcontainer/installation.json
```

This file describes:

- Required tooling and versions
- PowerShell module dependencies
- Execution assumptions for local development

The actual setup logic is implemented in:

```
.devcontainer/setup.ps1
```

Some setup steps may be **skipped or unnecessary** when running on Azure DevOps hosted agents, as those agents already include common tooling such as PowerShell and the Azure CLI.

## Using the dev container locally

To use the dev container:

1. Install Docker Desktop
2. Install Visual Studio Code
3. Install the **Dev Containers** extension
4. Open this repository in VS Code
5. Select **“Reopen in Container”** when prompted

Once started, the environment will closely mirror the runtime assumptions used by the pipeline.

## Why this exists

Providing a dev container aligns with Microsoft Cloud Adoption Framework (CAF) and Well-Architected guidance by:

- Reducing environment drift
- Improving repeatability and auditability
- Supporting secure and predictable development workflows
