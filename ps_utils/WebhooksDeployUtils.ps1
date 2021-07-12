function Init-TempFolder(
    [string] $tempDirectory,
    [string] $cliPackage
) {
    $script:tempDirectory = $tempDirectory
    $script:cliPath = Join-Path $tempDirectory "\migrator"

    Write-Output "`nExtracting cli to: $script:cliPath"
    Expand-Archive -path $cliPackage -destinationpath $script:cliPath

    # the zip archive contains a folder, so we set that as the actuall path
    $cliFolder = Get-ZipRootFolder $cliPackage
    $script:cliPath = Join-Path (Join-Path $script:cliPath $cliFolder) "\WebhookService.Migrate.Cli.exe"
}

function Remove-TempFolder {
    # Cleans temp folder where migration cli is extracted

    Write-Output ""
    Write-Verbose "Removing temporary folder $($script:tempDirectory)"
    Remove-Item $script:tempDirectory -Recurse -Force
}

function Run-SettingsMigrator(
    $orchWebConfigPath,
    $webhooksAppSettingPath
) {
    Set-Content -Path $webhooksAppSettingPath -Value '{}' -Force

    $args = "--webConfigFile ""$orchWebConfigPath""  --appSettingsFile ""$webhooksAppSettingPath"""

    Write-Output "Running cli with arguments: $args"

    $process = Start-Process $script:cliPath -ArgumentList $args -Wait -NoNewWindow -PassThru

    Write-Output "Process exitCode = $($process.ExitCode)"
    
    if($process.ExitCode)
    {
        Write-Error "Run-SettingsMigrator step exited with error."
        exit 1
    }
}