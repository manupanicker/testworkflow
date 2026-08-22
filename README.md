# Test Workflow

GitHub Actions proof-of-concept for provisioning and configuring Azure Windows VMs using Azure authentication and PowerShell.

## Architecture

GitHub Actions is the orchestration layer. YAML workflows control when and where automation runs, while PowerShell scripts contain the Windows/Azure implementation logic.

```text
GitHub Actions
      |
      +-- YAML workflow (orchestration)
      |
      +-- PowerShell scripts (implementation)
      |
      v
    Azure
      |
      v
 Azure Windows VM
```

The workflows use Azure VM Run Command to execute PowerShell inside Azure VMs. This does not require WinRM or RDP connectivity from the GitHub-hosted runner to the VM.

## Workflows

### 1. Create Windows Server 2022 VM

`Create-Windows2022-VM.yml`

Creates a Windows Server 2022 Azure VM using the configuration defined by the workflow and `Scripts/Create-Windows2022-VM.ps1`.

Current configuration includes:

- Resource Group: `CITRIX_BUILD`
- Location: `eastus`
- VNet: `vnet-eastus-2`
- Subnet: `snet-eastus-1`
- VM size: `Standard_D2as_v7`
- Windows Server 2022 Datacenter Small Disk Gen2
- Dynamic private IP / DHCP
- DNS: `172.16.0.4`
- Accelerated Networking enabled
- Boot Diagnostics enabled
- Automatic Windows updates
- Trusted Launch
- Secure Boot enabled
- vTPM enabled

The VM name is supplied when the workflow is run, allowing the same workflow to create multiple VMs.

### 2. Join VM to alphaq.com

`Domain-Join.yml`

Runs `Scripts/Domain-Join.ps1` inside the target VM through Azure VM Run Command.

The script is responsible for:

- Validating DNS
- Validating `alphaq.com` discovery
- Checking current domain membership
- Joining the VM to `alphaq.com`
- Applying the required Windows network configuration
- Restarting the VM after the domain join

The domain-join credentials are stored as GitHub repository secrets and are not committed to the repository.

## Repository Structure

```text
.github/
└── workflows/
    ├── Create-Windows2022-VM.yml
    └── Domain-Join.yml

Scripts/
├── Create-Windows2022-VM.ps1
└── Domain-Join.ps1

README.md
```

## Required GitHub Secrets

Create these repository secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_VM_ADMIN_USERNAME`
- `AZURE_VM_ADMIN_PASSWORD`
- `ALPHAQ_DOMAIN_JOIN_USERNAME`
- `ALPHAQ_DOMAIN_JOIN_PASSWORD`

The Azure identity used by the workflows must have the appropriate permissions on the Azure resources being managed, including permission to invoke VM Run Command.

## Running a Workflow

Go to **Actions**, select the required workflow, and choose **Run workflow**.

For VM creation, provide a unique VM name.

For domain joining, provide the name of an existing Azure VM.

## Design Principles

- **YAML controls the workflow.**
- **PowerShell performs the Windows/Azure operations.**
- Keep credentials in GitHub Secrets, never in YAML or PowerShell source.
- Use Azure APIs and VM Run Command rather than requiring WinRM access to Azure VMs.
- Keep provisioning and post-provisioning configuration as separate workflows so each stage can be tested independently.

## Future Automation

This repository can be extended with additional PowerShell-based workflows for:

- VM health checks
- Software installation
- Windows configuration
- Citrix VDA configuration
- Service validation
- Post-build validation
- MCS image preparation
