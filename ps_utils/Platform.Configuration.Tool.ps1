# LEGAL NOTICE: By installing and using this software, you (individual or legal entity) agree to the applicable LICENSE AGREEMENT available here: https://www.uipath.com/developers/all-editions/license-agreement. Please read it carefully. If you disagree with the license agreement, do not install or use the software and delete it from your computer.
<#
    .SYNOPSIS
        Check the identity server signing certificate used for several common errors.

    .DESCRIPTION
        Checks the identity server signing certificate
        1. Exists
        2. Can be validated
        3. Has the appropriate key size
        4. Has a private key accessible to the app pool user
        5. Has the identity server host as a subject

        If any of the above are false, the script will output an error
#>
#Requires -Modules WebAdministration
using namespace System.Security.AccessControl;
param (
    # The name of the Orchestrator site to check.
    [Parameter(ValueFromPipeline=$true)]
    [string]$SiteName="UiPath Orchestrator"
)

Write-Host "Checking signing certificate validity for site $SiteName\Identity"

$identitySite = Get-Item IIS:\Sites\$SiteName\Identity
$identityPath = $identitySite.PhysicalPath

Write-Host "Getting certificate info from $identityPath\appsettings.Production.json"
$identityProductionConfig = Get-Content $identityPath\appsettings.Production.json | ConvertFrom-Json

$orchestratorSite = Get-Item IIS:\Sites\$siteName
$orchestratorPath = $orchestratorSite.PhysicalPath
$orchestratorconfigFilePath = Join-Path $orchestratorPath "UiPath.Orchestrator.dll.config"
$orchestratorWebConfig = [xml](Get-Content $orchestratorconfigFilePath)

if ($identityProductionConfig.ConfigEncryptionSettings) {
    Write-Error "appsettings.production.json is encrypted. Can't verify redirect uris"
} else {
    $sqlConnectionString = $identityProductionConfig.ConnectionStrings.DefaultConnection
    $redirectUri = $orchestratorWebConfig.configuration.appSettings.add | Where-Object { $_.key -eq 'ExternalAuth.System.OpenIdConnect.RedirectUri' } | Select-Object -ExpandProperty value
    $postLogoutUri = $orchestratorWebConfig.configuration.appSettings.add | Where-Object { $_.key -eq 'ExternalAuth.System.OpenIdConnect.PostLogoutRedirectUri' } | Select-Object -ExpandProperty value
    $countsql = "SELECT COUNT(*) AS countUris FROM [identity].[{0}] r JOIN [identity].[Clients] c ON c.[Id] = r.[ClientId] WHERE c.[ClientName] = 'Orchestrator.OpenId' AND r.[{1}] = '{2}'"
    $countRedirectUriSql = $countsql -f "ClientRedirectUris","RedirectUri",$redirectUri
    $countRedirectUri = (Invoke-Sqlcmd -ConnectionString $sqlConnectionString -Query $countRedirectUriSql).countUris
    $countPostLogoutUriSql = $countsql -f "ClientPostLogoutRedirectUris","PostLogoutRedirectUri",$postLogoutUri
    $countPostLogoutUri = (Invoke-Sqlcmd -ConnectionString $sqlConnectionString -Query $countPostLogoutUriSql).countUris

    if ($countRedirectUri -lt 1) {
        Write-Error "No redirect uris were found in the Identity Server database matching $redirectUri."
    }
    if ($countPostLogoutUri -lt 1) {
        Write-Error "No post logout redirect uris were found in the Identity Server database matching $postLogoutUri."
    }
}

$identityCertLocation = $identityProductionConfig.AppSettings.SigningCredentialSettings.StoreLocation.Location
$identityCertName = $identityProductionConfig.AppSettings.SigningCredentialSettings.StoreLocation.Name
$certPath = "Cert:\$identityCertLocation\My\$identityCertName"

Write-Host "Getting $certPath"

$cert = Get-Item $certPath

if (!$cert) {
    Write-Error "No certificate found at $certPath." -Category ObjectNotFound
    return
}

Write-Host "Verifying certificate"

if (!$cert.Verify()) {
    Write-Error "Could not verify $certPath." -TargetObject $cert
}

Write-Host "Checking certificate key size"

$certKeySize = $cert.PublicKey.Key.KeySize
if ($certKeySize -lt 2048) {
    Write-Error "Key size must be at least 2048 but was $certKeySize." -TargetObject $cert
}


Write-Host "Checking certificate private key access"

$appPoolName = $identitySite.applicationPool
$appPool = Get-Item IIS:\AppPools\$appPoolName

$appPoolUser = if($appPool.processModel.identityType -eq "ApplicationPoolIdentity") {
    $appPool.name
} else {
    $appPool.processModel.userName
}

$certPkAccess = $cert.PrivateKey.CspKeyContainerInfo.CryptoKeySecurity.Access
$userAccess = $certPkAccess | Where { $_.IdentityReference.Value -like "*\$appPoolUser" }

if (-not $userAccess) {
    $usersWithAccess = $certPkAccess.IdentityReference.Value -join ', '
    Write-Error "AppPool user $appPoolUser does not have access to the private key certificate. Users with access are $usersWithAccess. For help, see https://docs.uipath.com/orchestrator/docs/identity-server-troubleshooting#section-keyset-does-not-exist-error-after-installation"
} elseif ($userAccess.AccessControlType -eq "Deny") {
    Write-Error "AppPool user $appPoolUser is denied access to the private key certificate. For help, see https://docs.uipath.com/orchestrator/docs/identity-server-troubleshooting#section-keyset-does-not-exist-error-after-installation"
} elseif (-not (
        $userAccess.CryptoKeyRights.HasFlag([CryptoKeyRights]::GenericRead) -or
        $userAccess.CryptoKeyRights.HasFlag([CryptoKeyRights]::ReadData))) {
    Write-Error "AppPool user $appPoolUser is missing rights to the certificate private key. For help, see https://docs.uipath.com/orchestrator/docs/identity-server-troubleshooting#section-keyset-does-not-exist-error-after-installation"
}


Write-Host "Checking SSL certificate subject"

$binding = (Get-ChildItem -Path IIS:\SSLBindings | Where Sites -eq $siteName)[0]
$sslCertPath = "cert:\LocalMachine\$($binding.Store)\$($binding.Thumbprint)"
$sslCert = Get-Item $sslCertPath -ErrorAction SilentlyContinue

[URI]$orchestratorUri = $identityProductionConfig.AppSettings.OrchestratorUrl
$orchestratorHost = $orchestratorUri.DnsSafeHost

if (!$sslCert) {
    Write-Error "No certificate found at $sslCertPath." -Category ObjectNotFound
} elseif (-not ($sslCert.DnsNameList | where {$orchestratorHost -like $_})) {
    Write-Error "Orchestrator host $orchestratorHost is not a subject of the SSL certificate. Subjects are $($sslCert.DnsNameList)"
}


Write-Host "Checking AspNetCore module"

$aspNetCoreModule = Get-WebGlobalModule AspNetCoreModuleV2
if (-not $aspNetCoreModule) {
    Write-Error "AspNetCoreModuleV2 not found. Check that the ASP.NET Core Hosting Bundle properly is installed. https://docs.microsoft.com/en-us/aspnet/core/host-and-deploy/iis/?view=aspnetcore-3.1#install-the-net-core-hosting-bundle"
}

Write-Host "Checks complete."
