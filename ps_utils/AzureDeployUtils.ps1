function Ensure-AzureRm {

    $azureRmVersion = "6.13.1";

    Write-Output "`nLoading AzureRM module ... "

    if (Test-Path 'C:\Modules\azurerm_6.7.0\AzureRM\6.7.0\AzureRM.psd1') {
        Import-AzureRmModuleFromLocalMachine
    } else {
            if (!(Get-Module AzureRM)) {
                Import-Module AzureRM
                if ((Get-Module AzureRM).Version.Major -lt $azureRmVersion.Split(".")[0]) {
                    Write-Output "Updating AzureRM to $azureRmVersion"
                    Install-Module AzureRM -MinimumVersion $azureRmVersion -AllowClobber -Force
                }
            }
    }

    Write-Output "`nDone loading AzureRM module"
}

function Import-AzureRmModuleFromLocalMachine {

    $azureRMModuleLocationBaseDir = 'C:\Modules\azurerm_6.7.0'
    $azureRMModuleLocation = "$azureRMModuleLocationBaseDir\AzureRM\6.7.0\AzureRM.psd1"

    if ((Get-Module AzureRM)) {
        Write-Output "Unloading AzureRM module ... "
        Remove-Module AzureRM
    }

    Write-Output "Importing module $azureRMModuleLocation"
    $env:PSModulePath = $azureRMModuleLocationBaseDir + ";" + $env:PSModulePath

    $currentVerbosityPreference = $Global:VerbosePreference

    $Global:VerbosePreference = 'SilentlyContinue'
    Import-Module $azureRMModuleLocation -Verbose:$false
    $Global:VerbosePreference = $currentVerbosityPreference
}

function AuthenticateToAzure(
    [string] $azureAccountPassword,
    [string] $azureAccountApplicationId,
    [string] $azureSubscriptionId,
    [string] $azureAccountTenantId,
    [switch] $azureUSGovernmentLogin
) {

    $securePassword = $azureAccountPassword | ConvertTo-SecureString -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($azureAccountApplicationId, $securePassword)

    Write-Verbose "Attempting to log in to AzureRM"
    if ($azureUSGovernmentLogin) {
        $loginResult = Login-AzureRmAccount `
            -ServicePrincipal `
            -SubscriptionId $azureSubscriptionId `
            -TenantId $azureAccountTenantId `
            -Credential $credential `
            -Environment AzureUSGovernment
    } else {
        $loginResult = Login-AzureRmAccount `
            -ServicePrincipal `
            -SubscriptionId $azureSubscriptionId `
            -TenantId $azureAccountTenantId `
            -Credential $credential
    }

    if ($loginResult){
        Write-Output "Logged in to AzureRM"
    } else {
        Write-Error "Failed to log in to AzureRM"
        Exit 1
    }
}

function Stop-WebApplication (
    [string] $targetSlot,
    [string] $resourceGroupName,
    [string] $appServiceName
) {
    Write-Verbose "Stopping Web Application $appServiceName"

    $stopped = Stop-AzureRmWebAppSlot -ResourceGroupName $resourceGroupName -Name $appServiceName -Slot $targetSlot

    if ($stopped) {
        Write-Output "Stopped the application $appServiceName-$targetSlot"
    } else {
        Write-Error "Could not stop the application $appServiceName-$targetSlot, aborting."
        Exit 1
    }

    $waitTime = 5
    Write-Output "Waiting $waitTime seconds for $appServiceName-$targetSlot to shut down completely."
    Start-Sleep -Seconds $waitTime
}

function Start-WebApplication(
    [string] $targetSlot,
    [string] $resourceGroupName,
    [string] $appServiceName
) {
    Write-Verbose "Starting Web Application $appServiceName"

    $started = Start-AzureRmWebAppSlot -ResourceGroupName $resourceGroupName -Name $appServiceName -Slot $targetSlot

    if ($started){
        Write-Output "Started the application $appServiceName-$targetSlot"
    } else {
        Write-Error "Could not start the application $appServiceName-$targetSlot, try to start it manually."
    }
}

function Set-VirtualPath(
    [string] $resourceGroupName,
    [string] $appServiceName,
    [string] $virtualPath,
    [string] $rootFolder
) {
    $props = @{
        "virtualApplications" = @(
            @{
                "virtualPath"  = "/";
                "physicalPath" = "site\wwwroot";
            },
            @{
                "virtualPath"  = $virtualPath;
                "physicalPath" = "site\wwwroot\$rootFolder";
            }
        )
    }
    Write-Verbose "Adding following virtual paths to $appServiceName`n$($props| ConvertTo-Json)"
    Write-Output "Setting web app virtual path"
    try
    {
        Set-AzureRmResource `
            -ResourceGroupName $resourceGroupName `
            -ResourceType "Microsoft.Web/sites/config" `
            -ResourceName "$appServiceName/web" `
            -PropertyObject $props `
            -ApiVersion "2015-08-01" `
            -Force
    }
    catch
    {
        Write-Error "Failed to Set Virtual Paths for Identity Server Web App Service!`n`nPlease make sure the virtual paths have been set by either doing it manually or by re-running the script before using identity server."
    }
}


function Download-PublishProfile(
    [string] $targetSlot,
    [string] $resourceGroupName,
    [string] $appServiceName,
    [string] $outputPath
) {
    Write-Verbose "Downloading Publish Profile for $appServiceName"
    Get-AzureRmWebAppSlotPublishingProfile -OutputFile $outputPath -ResourceGroupName $resourceGroupName -Name $appServiceName -Slot $targetSlot | Out-Null
}

function Download-WebsiteFile([string] $websiteFilePath, [string] $outputPath, $publishProfile) {
    $fileUrl = if ($websiteFilePath.StartsWith("/")) {
        $publishProfile.FtpPublishUrl + $websiteFilePath
    } else {
        $publishProfile.FtpPublishUrl + "/" + $websiteFilePath
    }
    Download-File -url $fileUrl -userName $publishProfile.FtpUsername -password $publishProfile.FtpPassword -outputPath $outputPath
}

function Upload-WebsiteFile([string] $websiteFilePath, [string] $localFilePath, $publishProfile) {

    $fileUrl = if ($websiteFilePath.StartsWith("/")) {
        $publishProfile.FtpPublishUrl + $websiteFilePath
    } else {
        $publishProfile.FtpPublishUrl + "/" + $websiteFilePath
    }
        
    Upload-File -url $fileUrl -file $localFilePath -userName $publishProfile.FtpUsername -password $publishProfile.FtpPassword 
}

function Download-File([string] $url, [string] $userName, [string] $password, [string] $outputPath) {
    Write-Verbose "`nDownloading file from URL $url to $outputPath"
    $fileUri = New-Object System.Uri($url)

    $webClient = New-Object System.Net.WebClient
    $webClient.Credentials = New-Object System.Net.NetworkCredential($userName.Normalize(), $password.Normalize())
    $webClient.DownloadFile($fileUri, $outputPath)
}

function Upload-File([string] $url, [string] $file, [string] $userName, [string] $password) {
    Write-Verbose "`nUploading file from $file to $url"
    $fileUri = New-Object System.Uri($url)

    $webClient = New-Object System.Net.WebClient
    $webClient.Credentials = New-Object System.Net.NetworkCredential($userName.Normalize(), $password.Normalize())
    $webClient.UploadFile($fileUri, $file)
}

function Update-WebSiteSettings(
    $siteDetails, # @{ appServiceName, resourceGroupName }
    $newSettings
) {
    $appService = Get-AzureRmWebApp -Name $siteDetails.appServiceName -ResourceGroupName $siteDetails.resourceGroupName

    $appSettings = $appService.SiteConfig.AppSettings

    # setup the current app settings
    $settings = @{}
    ForEach ($setting in $appSettings) {
        $settings[$setting.Name] = $setting.Value
    }

    # adding new settings to the app settings
    ForEach ($it in $newSettings.Keys) {
        $value = $newSettings[$it]
        $settings[$it] = $value
        Write-Verbose "Updating $it to $value";
    }

    Write-Output "Updating azure website with new settings";

    # update will just replace all settings (does NOT do Upsert)
    $app = Set-AzureRMWebApp -AppSettings $settings -Name $siteDetails.appServiceName -ResourceGroupName $siteDetails.resourceGroupName

    Write-Output "Successfully updated azure website";
}