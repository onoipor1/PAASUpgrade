# Updating Azure PaaS Deployment from 19.10 to 20.10

---

### Notes
We created a PowerShell wrapper script to facilitate [updating process](https://docs.uipath.com/installation-and-upgrade/v2020.4/docs/the-azure-app-service-installation-script) for UiPath Orchestrator(Orchestrator) deployed on Azure App Service.
These PowerShell scripts will install `AzureRM modules` and `Microsoft Web Deploy 3.6` during the process if not already installed.

Additionally, these scripts will preserve parameters described [here](https://docs.uipath.com/installation-and-upgrade/v2020.10/docs/publish-orchestratorps1-parameters#parameters-persisted-on-update) and automatically migrate to formats compatible with Orchestrator version 20.10. However, these scripts are NOT capable of updating these parameters upon the update at this moment.  


### Prerequisites
- Orchestrator version 19.10 installed on Azure App Service
- Change Orchestrator's Azure App Service configuration as shown [here](https://docs.uipath.com/installation-and-upgrade/v2020.10/docs/publish-orchestratorps1-parameters)
- Deploy and configure two additional Azure App Services for [Identity](https://docs.uipath.com/installation-and-upgrade/v2020.10/docs/publish-identityserverps1-parameters) and [Webhooks](https://docs.uipath.com/installation-and-upgrade/v2020.10/docs/publish-webhooksps1-parameters)
  
### Steps

1. Download the zip file on your computer. [20.10 DOWNLOAD](http://download.uipath.com/versions/20.10.9/UiPathOrchestrator.zip)
2. Create a directory and unarchive the zip file into the directory 
3. Grab the [AZModules Zip](https://github.com/UiPath/Infrastructure/raw/main/Azure/Orchestrator/Other/AzModules.zip) and copy into directory in step 2.
4. Complete all the prerequisites specified earlier 
5. Backup necessary components including database(s) and configuration files for the Orchestrator. For more details, please refer to [this documentation](https://docs.uipath.com/installation-and-upgrade/v2020.10/docs/backup-and-restore)
6. Open PowerShell window and navigate to the directory created earlier
7. Initiate an update process for the Orchestrator:
   - Method 1 - Using your Azure account
```
    .\Update-UiPathOrchestratorPaaS.ps1 `
        -azureSubscriptionId  $azureSubscriptionId `
        -azureTenantId  $azureTenantId `
        -resourceGroupName  $resourceGroupName `
        -appServiceNameOrch  $appServiceNameOrch `
        -appServiceNameIdentity  $appServiceNameIdentity `
        -appServiceNameWebhooks  $appServiceNameWebhooks `
        -orchestratorUrl $orchestratorUrl `
        -identityServerUrl $identityServerUrl `
        -azureInteractiveLogin
```
  - Method 2 - Using Azure Enterprise App ID
```
    .\Update-UiPathOrchestratorPaaS.ps1 `
        -azureSubscriptionId  $azureSubscriptionId `
        -azureTenantId  $azureTenantId `
        -resourceGroupName  $resourceGroupName `
        -appServiceNameOrch  $appServiceNameOrch `
        -appServiceNameIdentity  $appServiceNameIdentity `
        -appServiceNameWebhooks  $appServiceNameWebhooks `
        -orchestratorUrl $orchestratorUrl `
        -identityServerUrl $identityServerUrl `
        -azureApplicationId $azureApplicationId `
        -azureApplicationSecret $azureApplicationSecret 
```

### List of Parameters

| Variable Name | Value | Type | Mandatory |
| ------------- | ------| -----| --------- |
|`azureSubscriptionId` | Azure Subscription ID | `String` |Yes |
|`azureTenantId` | Azure Tenant ID | `String` | Yes |
|`resourceGroupName` | Azure Resource Group Name | `String` | Yes | 
|`appServiceNameOrch` | Orchestrator Azure App Service Name | `String` | Yes |
|`appServiceNameIdentity` | Identity Azure App Service Name | `String` | Yes |
|`appServiceNameWebhooks` | Webhooks Azure App Service Name | `String` | Yes |
|`orchestratorUrl` | Orchestrator URL | `String` | Yes |
|`identityServerUrl` | Identity URL | `String` | Yes |
|`azureInteractiveLogin` | Authentication via User Credentials | `Switch` | No* |
|`isAzureUSGovEnvironment` | Authentication with Azure US Gov Cloud | `Switch` | No |
| `azureApplicationId` | Azure Enterprise App ID | `String` | No* |
| `azureApplicationSecret` | Azure Enterprise App Secret | `String` | No* |
\* Either `azureInteractiveLogin` or `azureApplicationId` and `azureApplicationSecret` must be specified to create a session with Azure.


