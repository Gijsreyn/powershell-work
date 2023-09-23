configuration ChocolateyInstaller
{
    param
    (
        [string]$ResourceGroupName,

        [string]$StorageAccountName,

        [string]$ContainerName = 'chocolatey',

        [Parameter()]
        [string]
        $Source = 'https://pkgs.dev.azure.com/<organizationName>/<projectName>/_packaging/Chocolatey/nuget/v2'
    )

    Import-DscResource -ModuleName cChoco
    Import-DscResource -ModuleName xPSDesiredStateConfiguration
    Import-DscResource -Module cAzureStorage  -ModuleVersion 1.0.0.1

    $AdoCredential = Get-AutomationPSCredential 'Ado'
    $StKey = Get-AutomationPSCredential 'SoftwareStorage'

    Node $AllNodes.NodeName
    {
        cChocoSource RemoveChocolateySource
        {
            Name   = 'chocolatey'
            Ensure = 'Absent'
        }

        cChocoSource InitializeSource
        {
            Name        = 'AdoPackages'
            Priority    = 0
            Ensure      = 'Present'
            source      = $Source
            Credentials = $AdoCredential
        }

        Foreach ($Feature in $Node.StandaloneSoftware)
        {
            cChocoPackageInstaller "$Feature"
            {
                name        = $Feature
                Ensure      = 'Present'
                AutoUpgrade = $True
                Source      = 'AdoPackages'
            }
        }

        Foreach ($Remote in $Node.RemoteSoftware)
        {
            cAzureStorage "Download_$($Remote.Name)"
            {
                Path                    = (Join-Path -Path $Env:Temp -ChildPath 'software')
                StorageAccountName      = $StorageAccountName
                StorageAccountContainer = $ContainerName
                StorageAccountKey       = $StKey.GetNetworkCredential().Password
                Blob                    = $Remote.RemoteFile
            }
            cChocoPackageInstaller "$($Remote.Name)"
            {
                name        = $Remote.Name
                Ensure      = 'Present'
                AutoUpgrade = $True
                Source      = 'AdoPackages'
                Params      = $Remote.Arguments
                DependsOn   = "[cAzureStorage]Download_$($Remote.Name)"
            }
        }
    }
}