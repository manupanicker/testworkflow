# Test Workflow

Proof-of-concept for executing PowerShell on an Azure Windows VM from GitHub Actions using Azure VM Run Command.

## Target

- Resource Group: `CITRIX_BUILD`
- VM: `ALPHAQDDC007VM`

## Required GitHub configuration

Create these repository secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

The Azure identity used by the workflow must have permission to invoke Run Command on the target VM.

## Run

Go to **Actions → Hello World Azure VM → Run workflow**.

The workflow runs on a GitHub-hosted runner, authenticates to Azure using OIDC, and invokes PowerShell inside the target Azure VM using `az vm run-command invoke`.
