Function _createAzAutomationCredential
{
    param ($Name, $Username, $Value, $ResourceGroupName, $AutomationAccountName)

    $Params = @{
        ResourceGroupName = $ResourceGroupName
        AutomationAccountName = $AutomationAccountName
        Name = $Name
        ErrorAction = 'SilentlyContinue'
    }
    $Credential = Get-AzAutomationCredential @Params
    if ($Credential)
    {
        Write-Information -MessageData ("Removing credential - {0}" -f $Name) -InformationAction Continue
        Remove-AzAutomationCredential @Params
    }

    $User = $Username
    $Password = ConvertTo-SecureString $Value -AsPlainText -Force
    $CredentialObject = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password

    $Params.Value = $CredentialObject
    Write-Information -MessageData ("Creating new credential - {0}" -f $Name) -InformationAction Continue
    New-AzAutomationCredential @Params
}

Function _getParameterAST
{
    param ($AST, $functionName)

    $parameter = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.ParamBlockAst] }, $true) | Where-Object { $_.parent.parent.name -eq $functionName }

    $parameter.parameters | Select-Object @{n = 'name'; e = { $_.name.variablepath.userpath } }, @{n = 'value'; e = { $_.defaultvalue.extent.text } }, @{ n = 'type'; e = { $_.staticType.name } }
}

Function _convertArrayToHash
{
    param ([array]$Array, $Delimeter = "=")

    $Split = $Array.Split(";")
    [hashtable]$Hash = @{}
    $Split.Foreach({
            $Group = $_.Split($Delimeter)
            $Hash += @{$Group[0] = $Group[1] }
        })

    $Hash
}

Function _validateParameters
{
    param ($DifferenceObject, $ReferenceObject)
    if ($DifferenceObject)
    {
        Write-Information -MessageData "Converting $DifferenceObject" -InformationAction Continue
        $Hash = _convertArrayToHash -Array $DifferenceObject
    }
    else
    {
        Write-Information -MessageData "Setting difference object to empty hash" -InformationAction Continue
        $Hash = @{}
    }

    if (-not $ReferenceObject)
    {
        Write-Information -MessageData "Setting reference object to empty hash" -InformationAction Continue
        $ReferenceObject = @{}
    }

    Write-Information -MessageData ("Comparing 'apples' with 'peers'") -InformationAction Continue
    $Result = Compare-Object -ReferenceObject $ReferenceObject -DifferenceObject ($Hash.Keys -as [array])
    if ($Result)
    {
        Throw ("Please check the input mandatory parameters in script and 'AdditionalParameter' passed in")
    }

    $Hash
}

Function _locateDataFile
{
    param ($SourceFile)
    $script:SourceName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile)
    $DataFileName = [string]::Concat($SourceName, ".", "Configuration", ".", "$Environment", ".psd1")
    try
    {
        $DataFilePath = (Resolve-Path "$SourceFile\..\..\Data\$DataFileName" -ErrorAction Stop).Path
    }
    catch
    {
        Write-Information -MessageData ("Data file '$DataFileName' not found in 'Data' directory") -InformationAction Continue
    }

    $DataFilePath
}

Function _registerAzDscNodeConfiguration
{
    param ([string[]]$NodeName, [string]$ResourceGroupName, [string]$AutomationAccountName)
    # TODO: Implement logic with Start-Job if more VMs are on-boarding at the same time
    foreach ($Node in $NodeName)
    {
        $NodeConfiguration = Get-AzAutomationDscNode -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Node

        # Check for node configuration
        $Source = [string]::Concat($SourceName, ".", $Node)

        if (-not $NodeConfiguration)
        {
            Write-Information -MessageData ("Node - {0} is not registered with {1}" -f $Node, $SourceName) -InformationAction Continue
            $Vm = Get-AzVM -Name $Node -Status
            if ($Vm.PowerState -ne 'VM running')
            {
                Write-Warning -Message ("Virtual machine - {0} skipping as it is not running" -f $Vm.Name)

                continue
            }

            Write-Information -MessageData ("Registering node - {0} with source {1}" -f $Vm.Name, $Source) -InformationAction Continue

            try
            {
                # TODO: Improve error handling when extension doesn't get installed
                Register-AzAutomationDscNode -AzureVMName $Vm.Name `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -AzureVMResourceGroup $Vm.ResourceGroupName `
                    -AzureVMLocation $Vm.Location `
                    -NodeConfigurationName $Source `
                    -ConfigurationMode ApplyAndAutocorrect `
                    -ConfigurationModeFrequencyMins 15 `
                    -RefreshFrequencyMins 30 `
                    -RebootNodeIfNeeded 1 `
                    -ActionAfterReboot ContinueConfiguration `
                    -ErrorAction Stop
            }
            catch
            {
                # Throw warning with inner exception for ADO
                Write-Warning -Message $_.Exception.InnerException
            }

        }

        if ($null -ne $NodeConfiguration.Id -and $NodeConfiguration.NodeConfigurationName -ne $Source)
        {
            Write-Information -MessageData ("Assigning node configuration - {0} to {1}" -f $Source, $Node) -InformationAction Continue
            $Params = @{
                NodeConfigurationName = $Source
                ResourceGroupName     = $ResourceGroupName
                Id                    = $NodeConfiguration.Id
                AutomationAccountName = $AutomationAccountName
                Force                 = $True
            }
            Set-AzAutomationDscNode @Params
        }

        Write-Information -MessageData ("Node - {0} up-to-date" -f $Node) -InformationAction Continue
    }
}

Function Initialize-DscAzConfiguration
{
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

        [AllowNull()]
        [Parameter(Mandatory = $False)]
        [string]
        $AdditionalParameter,

        [AllowNull()]
        [Parameter(Mandatory = $False)]
        [string]
        $Environment
    )

    Process
    {
        Write-Information -MessageData ("Importing file - {0}" -f $SourceFile) -InformationAction Continue
        $Params = @{
            SourcePath            = $SourceFile
            ResourceGroupName     = $ResourceGroupName
            AutomationAccountName = $AutomationAccountName
            Force                 = $True
            Published             = $True

        }
        Import-AzAutomationDscConfiguration @Params

        $DataFilePath = _locateDataFile $SourceFile

        # Parse the source file with AST
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($SourceFile, [ref]$null, [ref]$null)
        $Parameters = _getParameterAST $Ast

        # TODO: Get the mandatory parameters and if others needs to be specified we have to add them later
        $MandatoryParameters = $Parameters.Where({ $null -eq $_.value }).name

        $Data = _validateParameters -DifferenceObject $ParsedArguments -ReferenceObject $MandatoryParameters

        # TODO: Move logic out
        $Params = @{
            ConfigurationName     = $SourceName
            ResourceGroupName     = $ResourceGroupName
            AutomationAccountName = $AutomationAccountName
        }

        if ($DataFilePath)
        {
            Write-Information -MessageData ("Adding data file parameter on - {0} for 'Start-AzAutomationDscCompilationJob'" -f $DataFilePath) -InformationAction Continue
            $Params.ConfigurationData = (Import-PowerShellDataFile $DataFilePath)
        }

        if ($Data)
        {
            Write-Information -MessageData ("Adding parameter(s) parameter for 'Start-AzAutomationDscCompilationJob'") -InformationAction Continue
            $Params.Parameters = $Data
        }

        Write-Information -MessageData ("Start compiling file - '{0}'" -f $SourceName) -InformationAction Continue
        $Job = Start-AzAutomationDscCompilationJob @Params

        while ((Get-AzAutomationDscCompilationJob `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -Id $Job.Id).Status -ne "Completed")
        {
            Write-Information -MessageData ("Waiting for job id - {0} to finish" -f $Job.Id) -InformationAction Continue
            Start-Sleep -Seconds 60
        }
        Write-Information -MessageData ("Job completed {0}" -f $Job.Id) -InformationAction Continue

        $CompilationOutput = Get-AzAutomationDscCompilationJobOutput -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Id $Job.Id | Where-Object { $_.Type -eq 'Error' }

        if ($CompilationOutput)
        {
            $CompilationOutput | ForEach-Object {
                Write-Error -Message ("Compilation failed with error summary - {0}" -f $_.Summary)
            }

            return
        }

        $Job
    }
}

Function Register-DscAzConfiguration
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        [System.IO.FileInfo]
        $SourceFile,

        [Parameter(Mandatory = $True)]
        [string]
        $AutomationAccountName,

        [Parameter(Mandatory = $True)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $False)]
        [string[]]
        $NodeName

    )

    Process
    {
        # Locate the data file path to determine nodes
        $DataFilePath = _locateDataFile $SourceFile
        Write-Information "Got data file" -InformationAction Continue

        if ($NodeName)
        {
            # We will do it based on the node name
            _registerAzDscNodeConfiguration -NodeName $NodeName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        }
        elseif ($DataFilePath)
        {
            $NodeName = (Import-PowerShellDataFile $DataFilePath).AllNodes.NodeName
            # We can check if Node is empty but expect it to be filled
            _registerAzDscNodeConfiguration -NodeName $NodeName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        }
        else
        {
            # Nothing to register
        }
    }
}
