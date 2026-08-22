# Citrix Infrastructure Automation

GitHub Actions automation for building, configuring, validating, and removing Azure-based Citrix infrastructure.

## Architecture

The repository is designed as a **Citrix infrastructure build platform**, not just a Windows VM provisioning workflow.

GitHub Actions provides orchestration and operator-controlled inputs. **Bicep is the standard for Azure infrastructure**, while **PowerShell handles Windows and Citrix guest configuration**. Azure APIs and VM Run Command are used wherever possible so the solution does not depend on WinRM connectivity from the runner.

```text
                         GitHub Actions
                              |
                    YAML orchestration / inputs
                              |
                +-------------+-------------+
                |                           |
              Bicep                    PowerShell
                |                           |
        Azure infrastructure        Windows / Citrix config
                |                           |
                +-------------+-------------+
                              |
                         Azure Platform
                              |
          +-------------------+-------------------+
          |                   |                   |
        Network             VMs              Storage
          |                   |                   |
          |              Windows Server        OS/Data
          |                   |                   |
          |              Domain Join             |
          |                   |                   |
          |              Citrix VDA              |
          |                   |                   |
          +-------------------+-------------------+
                              |
                       Citrix Infrastructure
```

### Bicep - Azure infrastructure

Bicep is used for new Azure infrastructure work, including:

- Virtual machines
- NICs and IP configuration
- VNet/subnet integration
- DNS configuration
- Managed disks
- Trusted Launch
- Secure Boot
- vTPM
- Accelerated Networking
- Boot diagnostics
- Other Azure resources required by the Citrix platform

### PowerShell - Windows and Citrix configuration

PowerShell is used for operations inside Windows, including:

- Domain join and domain removal
- Windows configuration
- Network discovery configuration
- Windows services
- Software installation
- Citrix VDA installation and configuration
- Citrix-specific registry/configuration changes
- Citrix health checks
- Post-build validation
- MCS image preparation

### GitHub Actions - orchestration

YAML workflows remain intentionally thin. They provide:

- Manual workflow inputs
- Secrets and identity configuration
- Workflow sequencing
- Calling Bicep deployments
- Calling PowerShell scripts
- Validation and failure handling
- Operator-controlled destructive actions

## Current Workflows

### 1. Create Windows Server 2022 VM - Bicep

`Create-Windows2022-Bicep.yml`

Creates the Azure Windows Server 2022 VM that forms the base for subsequent Citrix configuration.

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

The VM name is supplied when the workflow is run, allowing the same infrastructure workflow to build multiple machines.

### 2. Join VM to alphaq.com

`Domain-Join.yml`

Runs `Scripts/Domain-Join.ps1` inside the target VM through Azure VM Run Command.

The script handles:

- DNS validation
- `alphaq.com` discovery validation
- Existing domain-membership checks
- Domain join
- Required Windows network configuration
- Network-discovery configuration
- Restart after domain join

Domain credentials are stored as GitHub repository secrets and are not committed to the repository.

### 3. Delete Windows Server 2022 VM

`Delete-Windows2022-VM.yml`

Removes a VM and its associated Azure resources after first removing the machine from `alphaq.com`.

The workflow requires the operator to enter `DELETE` as an explicit confirmation.

The deletion process is:

1. Validate that the VM exists.
2. Run `Scripts/Remove-From-Domain.ps1` inside the VM.
3. Remove the VM from `alphaq.com`.
4. Wait for the VM restart/shutdown.
5. Delete the Azure VM.
6. Delete the associated NIC(s).
7. Delete the OS disk.

If domain removal fails, destructive Azure cleanup should not proceed.

## Target Citrix Build Lifecycle

The repository will evolve toward a repeatable Citrix infrastructure factory:

```text
1. Provision Azure infrastructure
          |
          v
2. Build Windows Server VM
          |
          v
3. Configure DNS / network
          |
          v
4. Join alphaq.com
          |
          v
5. Install and configure Citrix VDA
          |
          v
6. Run Citrix / Windows health checks
          |
          v
7. Validate machine readiness
          |
          v
8. Prepare for MCS / image lifecycle
          |
          v
9. Retire / remove machine
```

The goal is to make each stage independently executable and repeatable while keeping infrastructure provisioning separate from guest configuration.

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

Additional Citrix-specific Bicep modules and PowerShell scripts should be added as the infrastructure factory expands.

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

- **GitHub Actions orchestrates.**
- **Bicep provisions Azure infrastructure.**
- **PowerShell configures Windows and Citrix.**
- Keep credentials in GitHub Secrets, never in source code.
- Prefer Azure APIs and VM Run Command instead of requiring WinRM access to VMs.
- Keep infrastructure provisioning separate from guest configuration.
- Keep domain join, Citrix configuration, health checks, and image preparation independently executable.
- Use Azure-native Bicep for new Azure infrastructure work rather than Terraform for this project.
- Build reusable components so the same workflows can create and configure multiple Citrix machines consistently.
