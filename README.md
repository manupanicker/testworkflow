# Citrix Infrastructure Automation

GitHub Actions automation for building, configuring, validating, and removing Azure-based Citrix infrastructure.

## Architecture

The repository is a **Citrix infrastructure build platform**, not just a Windows VM provisioning workflow. The target is to automate the lifecycle of the major Citrix components required to build a complete Citrix environment.

GitHub Actions provides orchestration and operator-controlled inputs. **Bicep is the standard for Azure infrastructure**, while **PowerShell handles Windows and Citrix software installation/configuration**. Azure APIs and VM Run Command are used wherever possible so the solution does not depend on WinRM connectivity from the runner.

```text
                              GitHub Actions
                                    |
                         YAML orchestration / inputs
                                    |
                    +---------------+---------------+
                    |                               |
                  Bicep                         PowerShell
                    |                               |
          Azure infrastructure          Windows / Citrix configuration
                    |                               |
                    +---------------+---------------+
                                    |
                              Azure Platform
                                    |
       +----------------------------+----------------------------+
       |                            |                            |
   Networking                  Infrastructure              Storage
       |                            |                            |
       |                     Windows Server VMs                 |
       |                            |                            |
       |              +-------------+-------------+              |
       |              |             |             |              |
       |            DDC          Director      Licensing         |
       |              |             |             |              |
       |              +-------------+-------------+              |
       |                            |                            |
       |                      StoreFront                         |
       |                            |                            |
       |                    Session Recording                    |
       |                            |                            |
       |                          VDA                            |
       |                            |                            |
       +----------------------------+----------------------------+
                                    |
                         Citrix Infrastructure
```

## Citrix Infrastructure Components

The automation platform is intended to build and configure the following Citrix infrastructure components:

### Citrix Licensing

- Licensing server installation
- Citrix licensing configuration
- License server connectivity and validation
- Licensing health checks

### Delivery Controllers (DDC)

- Windows Server preparation
- Citrix Delivery Controller installation
- Citrix site/database configuration as required
- Controller registration and health validation
- StoreFront/Controller connectivity validation

### Citrix Director

- Director installation/configuration
- Controller integration
- Director service validation
- Access and health checks

### StoreFront

- StoreFront installation
- Store configuration
- Store/Delivery Controller association
- Authentication configuration
- StoreFront service and connectivity validation

### Session Recording

- Session Recording installation
- Session Recording server configuration
- Session Recording Agent configuration where required
- Broker/service validation
- Recording infrastructure health checks

### Citrix VDA

- Windows VDA preparation
- Citrix VDA installation
- Delivery Group / Controller registration configuration
- VDA services and registration validation
- Citrix-specific configuration
- Post-build health checks

The exact installation options, versions, site configuration, database configuration, and Citrix-specific settings will be parameterized rather than hard-coded into the workflows.

## Technology Responsibilities

### Bicep - Azure infrastructure

Bicep provisions Azure resources required by the Citrix platform, including:

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
- Other Azure resources required by Citrix components

Bicep should describe **what Azure infrastructure is required**, not perform Windows or Citrix software installation.

### PowerShell - Windows and Citrix configuration

PowerShell performs operations inside Windows, including:

- Windows configuration
- Domain join and domain removal
- Windows services
- Prerequisite installation
- Citrix Licensing installation/configuration
- Delivery Controller installation/configuration
- Director installation/configuration
- StoreFront installation/configuration
- Session Recording installation/configuration
- VDA installation/configuration
- Citrix registry/configuration changes
- Citrix health checks
- Post-build validation
- MCS image preparation

PowerShell scripts should remain independently executable and parameterized so the same scripts can be used from multiple workflows.

### GitHub Actions - orchestration

YAML workflows remain intentionally thin. They provide:

- Manual workflow inputs
- Secrets and identity configuration
- Workflow sequencing
- Calling Bicep deployments
- Calling PowerShell scripts
- Validation and failure handling
- Operator-controlled destructive actions

## Target Citrix Build Lifecycle

The repository will evolve toward a repeatable end-to-end Citrix infrastructure factory:

```text
1. Provision Azure networking / infrastructure
                    |
                    v
2. Build Windows Server VMs
                    |
                    v
3. Configure DNS / network
                    |
                    v
4. Join alphaq.com
                    |
                    v
5. Build Citrix Licensing
                    |
                    v
6. Build Delivery Controllers
                    |
                    v
7. Build Director
                    |
                    v
8. Build StoreFront
                    |
                    v
9. Build Session Recording
                    |
                    v
10. Build Citrix VDA
                    |
                    v
11. Configure Citrix site / controllers / stores
                    |
                    v
12. Run Citrix and Windows health checks
                    |
                    v
13. Validate complete environment
                    |
                    v
14. Prepare VDA image / MCS lifecycle
                    |
                    v
15. Retire / remove infrastructure
```

Each component should have its own workflow or reusable automation module where practical, allowing individual components to be rebuilt or validated without rebuilding the entire environment.

## Current Workflows

### 1. Create Windows Server 2022 VM - Bicep

`Create-Windows2022-Bicep.yml`

Creates the Azure Windows Server 2022 VM that forms the base for subsequent Citrix component configuration.

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

As the Citrix infrastructure factory expands, add reusable Bicep modules and PowerShell scripts for each Citrix component rather than placing all component logic into one large script.

## Required GitHub Secrets

Create these repository secrets as required by the individual workflows:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_VM_ADMIN_USERNAME`
- `AZURE_VM_ADMIN_PASSWORD`
- `ALPHAQ_DOMAIN_JOIN_USERNAME`
- `ALPHAQ_DOMAIN_JOIN_PASSWORD`
- Citrix-specific credentials and installation parameters as required

Credentials must never be committed to the repository.

The Azure identity used by the workflows must have the appropriate permissions on the Azure resources being managed, including permission to invoke VM Run Command.

## Design Principles

- **GitHub Actions orchestrates.**
- **Bicep provisions Azure infrastructure.**
- **PowerShell installs and configures Windows and Citrix.**
- Keep YAML thin; business and configuration logic belongs in scripts/modules.
- Keep credentials in GitHub Secrets, never in source code.
- Prefer Azure APIs and VM Run Command instead of requiring WinRM access to VMs.
- Keep Azure infrastructure provisioning separate from guest configuration.
- Keep each Citrix component independently deployable and testable.
- Use Azure-native Bicep for new Azure infrastructure work rather than Terraform for this project.
- Build reusable components so the same automation can create complete Citrix environments consistently.
