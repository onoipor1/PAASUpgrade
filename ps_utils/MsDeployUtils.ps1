$msDeployExe = Join-Path ${env:ProgramFiles(x86)} "IIS\Microsoft Web Deploy V3\msdeploy.exe"

if (!(Test-Path $msDeployExe)) {
    Write-Error "No msdeploy.exe found at '$($msDeployExe)'"
    Exit 1
}

function Start-MsDeployProcess(
    [string] $arguments
) {
    Write-Verbose "Starting MsDeploy process"
    $process = Start-Process $msDeployExe -ArgumentList $arguments -Wait -NoNewWindow -PassThru

    return $process
}

function Build-MsDeployArgs([System.Collections.Hashtable] $parameters, $publishSettings) {
    Write-Verbose "Building MsDeploy Arguments"
    $site       = $publishSettings.SiteName
    $publishUrl = $publishSettings.PublishUrl
    $username   = $publishSettings.UserName
    $password   = $publishSettings.Password

    $msDeployArgs = "-verb:sync -source:package='$package' -dest:auto,ComputerName='https://$publishUrl/msdeploy.axd?site=$site',UserName='$userName',Password='$password',AuthType='Basic'"

    $parameters.GetEnumerator() | ForEach-Object {
        $msDeployArgs += " -setParam:name='$($_.Key)',value='$($_.Value)'"
    }

    return $msDeployArgs
}

function Read-PublishSettings([string] $publishSettingsFilePath) {
    Write-Verbose "Reading PublishSettings from $publishSettingsFilePath"
    if ($publishSettingsFilePath -and (Test-Path $publishSettingsFilePath)) {
        return Get-WDPublishSettings -FileName $publishSettingsFilePath
    } else {
        Write-Error "No publishSettings file found at '$($publishSettingsFilePath)'"
        Exit 1
    }
}


function Get-FtpPublishProfile([string] $publishPath) {
    Write-Verbose "Getting FTP publish profile based on $publishPath"
    $publishSettingsXml = New-Object System.Xml.XmlDocument

    $publishSettingsXml.Load($publishPath)

    $publishSettings = @{
        FtpPublishUrl = $publishSettingsXml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value;
        FtpUsername = $publishSettingsXml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value;
        FtpPassword = $publishSettingsXml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value;
    }

    return $publishSettings
}

