[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [String] $azureSubscriptionId,
    [Parameter(Mandatory = $true)]
    [String] $azureTenantId,
    [Parameter(Mandatory = $false)]
    [String] $azureApplicationId,
    [Parameter(Mandatory = $false)]
    [String] $azureApplicationSecret,
    [Parameter(Mandatory = $true)]
    [String] $resourceGroupName,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameOrch,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameIdentity,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameWebhooks,
    [Parameter(Mandatory = $false)]
    [String] $isTestAutomationEnabled = $false,
    [Parameter(Mandatory = $false)]
    [String] $hostAdminPassword,
    [Parameter(Mandatory = $false)]
    [String] $defaultTenantAdminPassword,
    [Parameter(Mandatory = $false)]
    [String] $storageType,
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
    [String] $webhookMigrateCliPackage = "UiPath.WebhookService.Migrator.Cli.zip",
    [Parameter(Mandatory = $false)]
    [Switch] $isAzureUSGovEnvironment,
    [Parameter(Mandatory = $false)]
    [Switch] $azureInteractiveLogin
)

$global:stepCount = 1

# check if AzureRM modules are already installed
if (!(Get-InstalledModule -Name AzureRM)) {
    Write-Output "$(Get-Date) Unzipping AZModules..."
    Expand-Archive -LiteralPath "./AzModules.zip" -DestinationPath . -Force
    Write-Output "$(Get-Date) Unzip done."
    Write-Output "$(Get-Date) Importing AzureRM modules..."
    $env:PSModulePath += ";$(Resolve-Path -Path .\AzModules)"
}

Import-Module -Name AzureRM -Global -Force
Import-Module -Name AzureRM.Storage -Global -Force
Import-Module -Name AzureRM.WebSites -Global -Force
Import-Module -Name AzureRM.Profile -Global -Force
Write-Output "$(Get-Date) Done importing AzureRM modules."

function Main {
    $ErrorActionPreference = "Stop"
    
    $logFile = "Installation.log"
    Start-Transcript -Path $logFile -Append -IncludeInvocationHeader

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

function InstallMSDeploy {
    Write-Output "$(Get-Date) Checking if MSDeploy exists or not..."
    $msdeployFile = "C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"
    if (!(Test-Path -Path $msdeployFile)) {
        Write-Output "$(Get-Date) Downloading and installing MSDeploy..."
        $msiExecArgs = "/i `"WebDeploy_amd64_en-US.msi`" /q /norestart LicenseAccepted=""0"" /l*vx `"webdeployInstallation.log`" "
        Start-Process "msiexec" -ArgumentList $msiExecArgs -Wait -PassThru
    }
}

function LoginToAzure {
    Write-Output "$(Get-Date) Login AzureUSGovEnvironment with Enterprise Application ID..."
    # check if needs to be logged into Azure US Gov
    if ($isAzureUSGovEnvironment) {
        if ($azureInteractiveLogin) {
            Write-Output "$(Get-Date) Login in Azure Gov with interactive login portal..."
            Connect-AzureRmAccount -Environment AzureUSGovernment -SubscriptionId $azureSubscriptionId
            # insert empty line to avoid this script to proceed without logging in Azure
            Write-Output "..."
            Write-Output "$(Get-Date) Logged into Azure Gov with interactive login portal"
        } else {
            Write-Output "$(Get-Date) Login Azure Gov with Enterprise Application ID..."
            $azureApplicationSecretEncrypted = $azureApplicationSecret | ConvertTo-SecureString -AsPlainText -Force
            $azureApplicationCredential = New-Object -TypeName System.Management.Automation.PSCredential ($azureApplicationId, $azureApplicationSecretEncrypted)
            Connect-AzureRmAccount -ServicePrincipal -Credential $azureApplicationCredential -TenantId $azureTenantId -SubscriptionId $azureSubscriptionId -ErrorAction Stop -Environment AzureUSGovernment
            Write-Output "$(Get-Date) Logged into AzureUSGovEnvironment with Azure enteprise applicaiton id." 
        }
    } else {
        if ($azureInteractiveLogin) {
            Write-Output "$(Get-Date) Login in Azure with interactive login portal..."
            Connect-AzureRmAccount -SubscriptionId $azureSubscriptionId
            # insert empty line to avoid this script to proceed without logging in Azure
            Write-Output "..."
            Write-Output "$(Get-Date) Logged into Azure with interactive login portal"
        } else {
            Write-Output "$(Get-Date) Login Azure with Enterprise Application ID..."
            $azureApplicationSecretEncrypted = $azureApplicationSecret | ConvertTo-SecureString -AsPlainText -Force
            $azureApplicationCredential = New-Object -TypeName System.Management.Automation.PSCredential ($azureApplicationId, $azureApplicationSecretEncrypted)
            Connect-AzureRmAccount -ServicePrincipal -Credential $azureApplicationCredential -TenantId $azureTenantId -SubscriptionId $azureSubscriptionId -ErrorAction Stop
            "$(Get-Date) Logged into Azure with Azure enteprise applicaiton id."
        }

    }
}

function PublishOrchestrator {
    Write-Output "******* $(Get-Date) Step $global:stepCount: Publish orchestrator script: ******* "
    $action = "Update"
    $OrchestratorArgs = @{
        action  = $action 
        unattended  = $true
        package  = $orchestratorPackage 
        stopApplicationBeforePublish  = $true
        azureSubscriptionId  = $azureSubscriptionId 
        azureAccountTenantId =  $azureTenantId 
        resourceGroupName =  $resourceGroupName 
        appServiceName =  $appServiceNameOrch
        noAzureAuthentication =  $true
        testAutomationFeatureEnabled = ([System.Convert]::ToBoolean($isTestAutomationEnabled)) 
        azureUSGovernmentLogin = ($isAzureUSGovEnvironment) 
        verbose = $true 
    }
    .\Publish-Orchestrator.ps1  @OrchestratorArgs
        
    IncrementStepCount
}

function PublishIdentityServer {
    Write-Output "******* $(Get-Date) Step $global:stepCount: publish identity script: *******"
    $action = "Deploy"
    $IdentityrArgs = @{
        action = $action 
        azureSubscriptionId = $azureSubscriptionId 
        azureAccountTenantId = $azureTenantId 
        package = $identityPackage 
        cliPackage = $identityCliPackage 
        stopApplicationBeforePublish = $true
        resourceGroupName = $resourceGroupName 
        appServiceName = $appServiceNameIdentity 
        orchestratorUrl = $orchestratorUrl 
        noAzureAuthentication = $true
        unattended = $true
        azureUSGovernmentLogin = ($isAzureUSGovEnvironment)
    }
    .\Publish-IdentityServer.ps1 @IdentityrArgs
        
    IncrementStepCount
}

function MigrateToIdentityServer {
    Write-Output "******* $(Get-Date) Step $global:stepCount: migrate to identity script: *******"
    .\MigrateTo-IdentityServer.ps1 `
        -cliPackage $identityCliPackage `
        -orchDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameOrch; targetSlot = "Production" } `
        -identityServerDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameIdentity; targetSlot = "Production" } `
        -orchestratorUrl $orchestratorUrl `
        -identityServerUrl $identityServerUrl `
        -noAzureAuthentication `
        -azureUSGovernmentLogin:($isAzureUSGovEnvironment)

    IncrementStepCount
}

function PublishWebhooks {
    Write-Output "*******  $(Get-Date) Step $global:stepCount: publish web hooks script: ******* "
    $action = "Deploy"
    $WebhookArgs = @{
        action = $action
        azureSubscriptionId = $azureSubscriptionId 
        appServiceName = $appServiceNameWebhooks 
        resourceGroupName = $resourceGroupName 
        package = $webhookServicePackage 
        stopApplicationBeforePublish = $true
        noAzureAuthentication = $true
        azureUSGovernmentLogin = ($isAzureUSGovEnvironment)
    }
    
    .\Publish-Webhooks.ps1 @WebhookArgs

    IncrementStepCount
}

function MigrateToWebhooks {
    Write-Output "*******  $(Get-Date) Step $global:stepCount: migrate to web hooks script: ******* "
    .\MigrateTo-Webhooks.ps1 `
        -cliPackage $webhookMigrateCliPackage `
        -orchDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameOrch; targetSlot = "Production" } `
        -webhookDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameWebhooks; targetSlot = "Production" } `
        -noAzureAuthentication `
        -azureUSGovernmentLogin:($isAzureUSGovEnvironment)
    
    IncrementStepCount
}

function IncrementStepCount {
    $global:stepCount++
}

Main
