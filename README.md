# Test Workflow

GitHub Actions automation for provisioning, configuring, validating, and removing Azure Windows VMs.

## Architecture

GitHub Actions is the orchestration layer. YAML workflows control when and where automation runs, while **Bicep handles Azure infrastructure** and **PowerShell handles Windows/guest configuration**.

```text
GitHub Actions
      |
      +-- YAML workflows (orchestration / inputs)
      |
      +-- Bicep (Azure infrastructure)
      |
      +-- PowerShell (Windows / guest configuration)
      |
      v
    Azure
      |
      v
 Azure Windows VM
```

The workflows use Azure APIs and Azure VM Run Command to execute PowerShell inside Azure VMs. This does not require WinRM or RDP connectivity from the GitHub-hosted runner to the VM.

## Workflows

### 1. Create Windows Server 2022 VM - Bicep

`Create-Windows2022-Bicep.yml`

Creates a Windows Server 2022 Azure VM using the Azure-native Bicep deployment.

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
- Configuring the required Windows network-discovery behavior
- Restarting the VM after the domain join

The domain-join credentials are stored as GitHub repository secrets and are not committed to the repository.

### 3. Delete Windows Server 2022 VM

`Delete-Windows2022-VM.yml`

Removes a VM and its associated Azure resources after first removing the machine from `alphaq.com`.

The workflow requires the operator to enter `DELETE` as an explicit confirmation before proceeding.

The deletion process is:

1. Validate the VM exists.
2. Run `Scripts/Remove-From-Domain.ps1` inside the VM through Azure VM Run Command.
3. Remove the VM from `alphaq.com`.
4. Wait for the VM restart/shutdown.
5. Delete the Azure VM.
6. Delete the associated NIC(s).
7. Delete the OS disk.

If domain removal fails, the workflow must not proceed with destructive cleanup.

## Repository Structure

```text
.github/
└── workflows/
    ├── Create-Windows2022-Bicep.yml
    ├── Domain-Join.yml
    └── Delete-Windows2022-VM.yml

Bicep/
├── main.bicep
└── main.bicepparam

Scripts/
├── Create-Windows2022-VM.ps1
├── Domain-Join.ps1
└── Remove-From-Domain.ps1

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

For VM deletion, provide the VM name and type `DELETE` as the confirmation.

## Design Principles

- **YAML controls the workflow.**
- **Bicep provisions Azure infrastructure.**
- **PowerShell performs Windows/guest operations.**
- Keep credentials in GitHub Secrets, never in YAML or PowerShell source.
- Use Azure APIs and VM Run Command rather than requiring WinRM access to Azure VMs.
- Keep provisioning, domain configuration, and destructive cleanup as separate workflows so each stage can be tested independently.
- Use Azure-native Bicep for new Azure infrastructure work rather than Terraform for this project.

## Future Automation

This repository can be extended with additional PowerShell-based workflows for:

- VM health checks
- Software installation
- Windows configuration
- Citrix VDA configuration
- Service validation
- Post-build validation
- MCS image preparation
