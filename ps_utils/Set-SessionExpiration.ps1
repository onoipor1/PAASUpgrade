Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)] [string]$SiteName="UiPath Orchestrator",
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)] [string]$IdentityApplicationName="Identity",
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)] [int]$ExpirationMins=30
)

$ErrorActionPreference="Stop"

Import-Module WebAdministration

function UpdateIdentityCookieConfiguration([string] $ConfigFile, [int] $CookieExpirationMins)
{
    $json=Get-Content $ConfigFile | ConvertFrom-Json
    $json.AppSettings."CookieExpireMinutes"=$CookieExpirationMins
    $json | ConvertTo-Json -Depth 100 | Set-Content $ConfigFile
    
    Write-Host "Identity configuration file $ConfigFile was successfully updated." -ForegroundColor Green
}

$siteConfigFile=Get-Item "IIS:\Sites\$SiteName\web.config"
[XML]$siteConfig=Get-Content $siteConfigFile.FullName

$cookieExpiration=$siteConfig.configuration.appSettings.add | where key -EQ "Auth.Cookie.Expire"
if ($cookieExpiration -ne $null)
{
    $cookieExpiration.SetAttribute('value', $ExpirationMins)
}
else
{
    $newSettingNode=$siteConfig.configuration.appSettings.OwnerDocument.CreateElement("add")

    $attrib=$newSettingNode.OwnerDocument.CreateAttribute("key")
    $attrib.Value="Auth.Cookie.Expire"
    $newSettingNode.Attributes.Append($attrib)

    $attrib=$newSettingNode.OwnerDocument.CreateAttribute("value")
    $attrib.Value=$ExpirationMins
    $newSettingNode.Attributes.Append($attrib)

    $siteConfig.configuration.appSettings.AppendChild($newSettingNode)
}

$siteConfig.Save($siteConfigFile.FullName)
Write-Host "Orchestrator configuration file $siteConfigFile was successfully updated." -ForegroundColor Green

$root=Get-Item "IIS:\Sites\$SiteName"
$identityConfigFile=Join-Path -Path $root.physicalPath -ChildPath "Identity\appsettings.production.json"
if (Test-Path $identityConfigFile)
{
    UpdateIdentityCookieConfiguration -ConfigFile $identityConfigFile -CookieExpirationMins $ExpirationMins
}
else
{
    $identityConfigFile=Join-Path -Path $root.physicalPath -ChildPath "Identity\appsettings.json"

    if (Test-Path $identityConfigFile)
    {
        UpdateIdentityCookieConfiguration -ConfigFile $identityConfigFile -CookieExpirationMins $ExpirationMins
    }
    else
    {
        Write-Host "Identity configuration file was not found" -ForegroundColor Red
    }
}

$identityApp = Get-WebApplication -Site $SiteName -Name $IdentityApplicationName
if ($identityApp -ne $null)
{
    Restart-WebAppPool $identityApp.applicationPool
    Write-Host "$IdentityApplicationName application pool was restarted" -ForegroundColor Yellow
}
else
{
    Write-Host "Web application $IdentityApplicationName was not found" -ForegroundColor Red
}




