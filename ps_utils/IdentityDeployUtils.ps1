$script:tempDirectory = $null
$script:cliPath = $null

function Init-IdentityTempFolder(
    [string] $tempDirectory,
    [string] $cliPackage
) {
    $script:tempDirectory = $tempDirectory
    $script:cliPath = Join-Path $tempDirectory "\migrator"

    Write-Output "`nExtracting cli to: $script:cliPath"
    Expand-Archive -path $cliPackage -destinationpath $script:cliPath

    # the zip archive contains a folder, so we set that as the actuall path
    $script:cliPath = Join-Path $script:cliPath "\DataMigratorCli\UiPath.DataMigrator.Cli.exe"
}

function Remove-IdentityTempFolder {
    # Cleans temp folder where migration cli is extracted

    Write-Output ""
    Write-Verbose "Removing temporary folder $($script:tempDirectory)"
    Remove-Item $script:tempDirectory -Recurse -Force
}

function Remove-ClientConfig (
    $configFile 
) {
    # Removes the temp file where client details are saved

    Write-Output ""
    Write-Verbose "Removing temporary client configuration file"
    Remove-Item $configFile -Force
}

function Run-DbMigrator (
    [string] $connectionString
) {
    $args = "install -d ""$connectionString"" -r"

    Write-Output "Running cli with arguments: $args"

    # later maybe move to actual exe
    $process = Start-Process $script:cliPath -ArgumentList $args -Wait -NoNewWindow -PassThru

    Write-Output "Process exitCode = $($process.ExitCode)"
    
    if($process.ExitCode)
    {
        Write-Error "Run-DbMigrator step exited with error."
        exit 1
    }
}

function Run-DataMigrator(
    $orchConnectionString,
    $identityConnectionString,
    $orchWebConfigPath,
    $identityServerUrl
) {
    $args = 
        "migrate -s ""$orchConnectionString"" -d ""$identityConnectionString"" -b 5000 " +
        "-w ""$orchWebConfigPath"" -i ""$identityServerUrl"""

    Write-Output "Running cli with arguments: $args"

    $process = Start-Process $script:cliPath -ArgumentList $args -Wait -NoNewWindow -PassThru -ErrorAction Stop

    Write-Output "Process exitCode = $($process.ExitCode)"

    if($process.ExitCode)
    {
        Write-Error "Run-DataMigrator step exited with error."
        exit 1
    }
}

function Run-SeedMigrator(
    $identityConnectionString,
    $orchestratorUrl,
    $configFile  # ex: config.json
) {
    $args = "seed -o ""$configFile"" -d ""$identityConnectionString"" -u ""$orchestratorUrl"" "

    Write-Output "Running cli with arguments: $args"

    $process = Start-Process $script:cliPath -ArgumentList $args -Wait -NoNewWindow -PassThru -ErrorAction Stop

    Write-Output "Process exitCode = $($process.ExitCode)"

    if($process.ExitCode)
    {
        Write-Error "Run-SeedMigrator step exited with error."
        exit 1
    }
}

function Check-InstalledAV {
    try
    {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        if ($osInfo.ProductType -eq 1)
        {
            # Client OS
            $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction Stop
        }
        else
        {
            # Server OS
            $computerName = $env:computername
            $filter = "antivirus|symantec|kaspersky|mcafee|avast|eset security|malwarebytes|webroot"

            $av = @()

            $hive = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $computerName)
            $regPathList = "SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                           "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

            foreach($regPath in $regPathList) {
                if($key = $hive.OpenSubKey($regPath)) {
                    if($subkeyNames = $key.GetSubKeyNames()) {
                        foreach($subkeyName in $subkeyNames) {
                            $productKey = $key.OpenSubKey($subkeyName)
                            $productName = $productKey.GetValue("DisplayName")
                            $productVersion = $productKey.GetValue("DisplayVersion")
                            $productComments = $productKey.GetValue("Comments")
                            if(($productName -match $filter) -or ($productComments -match $filter)) {
                                $resultObj = [PSCustomObject]@{
                                    Product = $productName
                                    Comments = $productComments
                                }
                                $av += $resultObj
                            }
                        }
                    }
                }
                $key.Close()
            }
        }
        
        if (@($av).Count -gt 0)
        {
            Write-Host "Antivirus software detected. Please ensure your security settings do not interfere with the installation process."
        }
    }
    catch
    {
        Write-Verbose "AV detection failed"
    }
}