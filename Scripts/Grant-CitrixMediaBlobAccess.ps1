[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$PrincipalObjectId
)

$ErrorActionPreference = 'Stop'

Write-Output '============================================================'
Write-Output 'Grant Citrix Media Blob Read Access'
Write-Output '============================================================'
Write-Output "Storage account : $StorageAccountName"
Write-Output "Resource group  : $ResourceGroupName"
Write-Output "Principal       : $PrincipalObjectId"

$storage = Get-AzStorageAccount `
    -ResourceGroupName $ResourceGroupName `
    -Name $StorageAccountName `
    -ErrorAction Stop

$scope = $storage.Id
$roleName = 'Storage Blob Data Reader'

$existing = Get-AzRoleAssignment `
    -ObjectId $PrincipalObjectId `
    -RoleDefinitionName $roleName `
    -Scope $scope `
    -ErrorAction SilentlyContinue

if ($existing) {
    Write-Output 'Storage Blob Data Reader is already assigned at the storage-account scope.'
}
else {
    New-AzRoleAssignment `
        -ObjectId $PrincipalObjectId `
        -RoleDefinitionName $roleName `
        -Scope $scope `
        -ErrorAction Stop | Out-Null

    Write-Output 'Storage Blob Data Reader assigned successfully.'
}

Write-Output 'Role assignment:'
Get-AzRoleAssignment `
    -ObjectId $PrincipalObjectId `
    -RoleDefinitionName $roleName `
    -Scope $scope `
    -ErrorAction Stop |
    Select-Object RoleDefinitionName, ObjectType, Scope |
    Format-Table -AutoSize |
    Out-String |
    Write-Output

Write-Output 'Completed.'
