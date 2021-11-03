[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [String] $azureSubscriptionId,
    [Parameter(Mandatory = $true)]
    [String] $azureTenantId,
    [Parameter(Mandatory = $true)]
    [String] $azureMSIApplicationId,
    [Parameter(Mandatory = $true)]
    [String] $resourceGroupName,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameOrch,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameIdentity,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameWebhooks,
    [Parameter(Mandatory = $true)]
    [String] $isTestAutomationEnabled,
    [Parameter(Mandatory = $false)]
    [String] $hostAdminPassword,
    [Parameter(Mandatory = $false)]
    [String] $defaultTenantAdminPassword,
    [Parameter(Mandatory = $false)]
    [String] $storageLocation,
    [Parameter(Mandatory = $false)]
    [String] $redisConnectionString,
    [Parameter(Mandatory = $false)]
    [String] $azureSignalRConnectionString,
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (($_ -as [System.URI]).AbsoluteURI -eq $null) { throw "Invalid" } return $true })]
    [String] $identityServerUrl,
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (($_ -as [System.URI]).AbsoluteURI -eq $null) { throw "Invalid" } return $true })]
    [String] $orchestratorUrl,
    [Parameter(Mandatory = $false)]
    [String] $insightsKey,
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath orchestrator web package is not valid." } return $true })]
    [String] $orchestratorPackage = "UiPath.Orchestrator.Web.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath identity web package is not valid." } return $true })]
    [String] $identityPackage = "UiPath.IdentityServer.Web.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath identity migrator package is not valid." } return $true })]
    [String] $identityCliPackage = "UiPath.IdentityServer.Migrator.Cli.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath webhooks web package is not valid." } return $true })]
    [String] $webhookServicePackage = "UiPath.WebhookService.Web.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath webhooks cli package is not valid." } return $true })]
    [String] $webhookMigrateCliPackage = "UiPath.WebhookService.Migrator.Cli.zip"    
    [Parameter(Mandatory = $false)]
    [Switch] $isAzureUSGovEnvironment,
    [Parameter(Mandatory = $false)]
    [Switch] $azureInteractiveLogin
)
$global:stepCount = 1

Write-Output "$(Get-Date) Unzipping ps_utils..."
Expand-Archive -LiteralPath "./ps_utils.zip" -DestinationPath . -Force
Write-Output "$(Get-Date) Unzipping AZModules..."
Expand-Archive -LiteralPath "./AzModules.zip" -DestinationPath . -Force
Write-Output "$(Get-Date) Unzip done."

Write-Output "$(Get-Date) Importing Az modules..."
$env:PSModulePath += ";$(Resolve-Path -Path .\AzModules)"
Import-Module -Name Az -Global -Force
Import-Module -Name Az.Storage -Global -Force
Import-Module -Name Az.WebSites -Global -Force
Import-Module -Name Az.Profile -Global -Force
Write-Output "$(Get-Date) Done importing Az modules."

Write-Output "$(Get-Date) Importing custom modules..."
Import-Module ([System.IO.Path]::GetFullPath((Join-Path (Get-Location) "./AzureUtils.psm1"))) -Global -Force
Write-Output "$(Get-Date) Done importing custom modules..."

function Main {
    $ErrorActionPreference = "Stop"
    
    $logFile = "Installation.log"
    Start-Transcript -Path $logFile -Append -IncludeInvocationHeader

    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

    InstallMSDeploy
    LoginToAzure
    PublishOrchestrator
    PublishIdentityServer
    MigrateToIdentityServer
    PublishWebhooks
    MigrateToWebhooks
    Write-Output " ******* $(Get-Date) Orchestrator installation complete *******"
    Stop-Transcript
    }
}

function InstallMSDeploy {
    Write-Output "$(Get-Date) Installing MSDeploy..."
    $msiExecArgs = "/i `"WebDeploy_amd64_en-US.msi`" /q /norestart LicenseAccepted=""0"" /l*vx `"webdeployInstallation.log`" "
    Start-Process "msiexec" -ArgumentList $msiExecArgs -Wait -PassThru
    $msdeployFile = "C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"

    if (Test-Path $msdeployFile) {
        Write-Output "$(Get-Date) MSDeploy path valid: $msdeployFile"
    }
    else {
        Write-Output "$(Get-Date) MSDeploy path invalid: $msdeployFile"
        Exit 1
    }
}

function LoginToAzure {
    Write-Output "$(Get-Date) Login AzureUSGovEnvironment with Enterprise Application ID..."
    # check if needs to be logged into Azure US Gov
    if ($isAzureUSGovEnvironment) {
        if ($azureInteractiveLogin) {
            Write-Output "$(Get-Date) Login in Azure Gov with interactive login portal..."
            Connect-AzAccount -Environment AzureUSGovernment -SubscriptionId $azureSubscriptionId
            # insert empty line to avoid this script to proceed without logging in Azure
            Write-Output "..."
            Write-Output "$(Get-Date) Logged into Azure Gov with interactive login portal"
        } else {
            Write-Output "$(Get-Date) Login Azure Gov with Enterprise Application ID..."
            $azureApplicationSecretEncrypted = $azureApplicationSecret | ConvertTo-SecureString -AsPlainText -Force
            $azureApplicationCredential = New-Object -TypeName System.Management.Automation.PSCredential ($azureApplicationId, $azureApplicationSecretEncrypted)
            Connect-AzAccount -ServicePrincipal -Credential $azureApplicationCredential -TenantId $azureTenantId -SubscriptionId $azureSubscriptionId -ErrorAction Stop -Environment AzureUSGovernment
            Write-Output "$(Get-Date) Logged into AzureUSGovEnvironment with Azure enteprise applicaiton id." 
        }
    } else {
        if ($azureInteractiveLogin) {
            Write-Output "$(Get-Date) Login in Azure with interactive login portal..."
            Connect-AzAccount -SubscriptionId $azureSubscriptionId
            # insert empty line to avoid this script to proceed without logging in Azure
            Write-Output "..."
            Write-Output "$(Get-Date) Logged into Azure with interactive login portal"
        } else {
            Write-Output "$(Get-Date) Login Azure with Enterprise Application ID..."
            $azureApplicationSecretEncrypted = $azureApplicationSecret | ConvertTo-SecureString -AsPlainText -Force
            $azureApplicationCredential = New-Object -TypeName System.Management.Automation.PSCredential ($azureApplicationId, $azureApplicationSecretEncrypted)
            Connect-AzAccount -ServicePrincipal -Credential $azureApplicationCredential -TenantId $azureTenantId -SubscriptionId $azureSubscriptionId -ErrorAction Stop
            "$(Get-Date) Logged into Azure with Azure enteprise applicaiton id."
        }

    }
}


function PublishOrchestrator {
    Write-Output "******* $(Get-Date) Step $global:stepCount: Publish orchestrator script: ******* "
    
    .\Publish-Orchestrator.ps1 `
        -action "Update" `
        -unattended `
        -package $orchestratorPackage `
        -stopApplicationBeforePublish `
        -resourceGroupName $resourceGroupName `
        -appServiceName $appServiceNameOrch `
        -useQuartzClustered `
        -redisConnectionString $redisConnectionString `
        -azureSignalRConnectionString $azureSignalRConnectionString `
        -hostAdminPassword $hostAdminPassword `
        -defaultTenantAdminPassword $defaultTenantAdminPassword `
        -storageType "Azure" `
        -storageLocation $storageLocation `
        -noAzureAuthentication `
        -testAutomationFeatureEnabled:([System.Convert]::ToBoolean($isTestAutomationEnabled)) `
        -verbose
        
    IncrementStepCount
}

function PublishIdentityServer {
    Write-Output "******* $(Get-Date) Step $global:stepCount: publish identity script: *******"
    .\Publish-IdentityServer.ps1 `
        -action Deploy `
        -package $identityPackage `
        -cliPackage $identityCliPackage `
        -stopApplicationBeforePublish `
        -resourceGroupName $resourceGroupName `
        -appServiceName $appServiceNameIdentity `
        -orchestratorUrl $orchestratorUrl `
        -noAzureAuthentication `
        -unattended
        
    IncrementStepCount
}

function MigrateToIdentityServer {
    Write-Output "******* $(Get-Date) Step $global:stepCount: migrate to identity script: *******"
    .\MigrateTo-IdentityServer.ps1 `
        -cliPackage $identityCliPackage `
        -orchDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameOrch; targetSlot = "Production" } `
        -identityServerDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameIdentity; targetSlot = "Production" } `
        -identityServerUrl $identityServerUrl `
        -orchestratorUrl $orchestratorUrl `
        -noAzureAuthentication

    IncrementStepCount
}

function PublishWebhooks {
    Write-Output "*******  $(Get-Date) Step $global:stepCount: publish web hooks script: ******* "
    .\Publish-Webhooks.ps1 `
        -action "Deploy" `
        -appServiceName $appServiceNameWebhooks `
        -resourceGroupName $resourceGroupName `
        -package $webhookServicePackage `
        -stopApplicationBeforePublish `
        -noAzureAuthentication

    IncrementStepCount
}

function MigrateToWebhooks {
    Write-Output "*******  $(Get-Date) Step $global:stepCount: migrate to web hooks script: ******* "
    .\MigrateTo-Webhooks.ps1 `
        -cliPackage $webhookMigrateCliPackage `
        -orchDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameOrch; targetSlot = "Production" } `
        -webhookDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameWebhooks; targetSlot = "Production" } `
        -noAzureAuthentication
    
    IncrementStepCount
}

function IncrementStepCount {
    $global:stepCount++
}

function isAzureUSGovEnvironment {
    $azEnvironment = Get-AzCloudEnvironment
    if ($azEnvironment -eq "AzureUSGovernmentCloud") {
        return $true
    }
    else {
        return $false
    }
}

Main
