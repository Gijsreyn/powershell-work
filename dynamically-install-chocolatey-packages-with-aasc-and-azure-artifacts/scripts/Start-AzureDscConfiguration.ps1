[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True)]
    [string]
    $AutomationAccountName,

    [Parameter(Mandatory = $True)]
    [string]
    $ResourceGroupName,

    [Parameter(Mandatory = $True)]
    [System.IO.FileInfo]
    $SourceFile,

    [Parameter(Mandatory = $True)]
    [string]
    $StorageAccountName,

    [Parameter(Mandatory = $True)]
    [string]
    $AdoToken,

    [AllowNull()]
    [Parameter(Mandatory = $False)]
    [string]
    $AdditionalParameter,

    [Parameter(Mandatory = $False)]
    [string[]]
    $NodeName,

    [AllowNull()]
    [Parameter(Mandatory = $False)]
    [string]
    $Environment

)

Import-Module $PSScriptRoot\Initialize-DscAzConfiguration.psm1 -Force

_createAzAutomationCredential -Name "Ado" `
    -Username "AzureDevOpsUser" `
    -Value $AdoToken `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName

$Key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].value

_createAzAutomationCredential -Name "SoftwareStorage" `
    -Username $StorageAccountName `
    -Value $Key `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName

$Params = @{
    AutomationAccountName = $AutomationAccountName
    ResourceGroupName     = $ResourceGroupName
    SourceFile            = $SourceFile
    AdditionalParameter   = $AdditionalParameter
    Environment           = $Environment
}

Initialize-DscAzConfiguration @Params

Register-DscAzConfiguration -SourceFile $SourceFile `
    -AutomationAccountName $AutomationAccountName `
    -ResourceGroupName $ResourceGroupName
