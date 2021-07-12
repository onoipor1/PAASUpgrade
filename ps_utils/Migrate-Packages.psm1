param(
    [parameter(Mandatory=$true)]
    [string] $msdeployPath,

    [parameter(Mandatory=$true)]
    [string] $migratorPath,

    [object] $publishSettings,

    [string] $connectionString,

    [string] $storageType,

    [string] $storageLocation,

    [string] $librariesPath,

    [string] $processesPath,

    [string] $instanceKey,

    [switch] $unattended
)

function UploadMigrator {
    $site = $publishSettings.SiteName
    $publishUrl = $publishSettings.PublishUrl
    $username = $publishSettings.UserName
    $password = $publishSettings.Password
    $target = './PackagesMigration'

    $args = "-verb:sync -source:contentPath='$migratorPath' -dest:contentPath='$target',ComputerName='https://$publishUrl/msdeploy.axd?site=$site',UserName='$userName',Password='$password',AuthType='Basic' -enableRule:DoNotDeleteRule"

    Write-Host "Deploying package migrator"

    $proccess = Start-Process $msdeployPath -ArgumentList $args -Wait -NoNewWindow -PassThru

    if ($proccess.ExitCode) {
        throw "Failed to deploy Packages Migrator."
    }
}

function GetRequestUrl($jobName) {
    $address = $publishSettings.PublishUrl
    return ("https://{0}/api/triggeredwebjobs/{1}" -f $address, $jobName)
}

function GetRequestAuth {
    $username = $publishSettings.UserName
    $password = $publishSettings.Password
    return [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))
}

function UploadJob($jobName, $jobFile) {
    $requestUrl = GetRequestUrl $jobName
    $requestAuth = GetRequestAuth
    $requestHeaders = @{
        'Content-Disposition' = ("attachment; filename={0}" -f $jobFile.Name)
        'Authorization' = ("Basic {0}" -f $requestAuth)
    }

    $response = Invoke-WebRequest -Uri $requestUrl -Headers $requestHeaders -InFile $jobFile -Method Put -UseBasicParsing
    if ($response.StatusCode -ne 200) {
        throw "Packages Migration: Upload webjob failed. $response"
    }
}

function StartJob($jobName) {
    $requestUrl = ("{0}/run" -f (GetRequestUrl $jobName))
    $requestAuth = GetRequestAuth
    $requestHeaders = @{
        'Content-Type' = 'application/json'
        'Authorization' = ("Basic {0}" -f $requestAuth)
    }

    $response = Invoke-WebRequest -Uri $requestUrl -Headers $requestHeaders -Method Post -UseBasicParsing
    if ($response.StatusCode -ne 202) {
        throw "Packages Migration: Start webjob failed. $response"
    }
}

function GetJobModel($jobName) {
    $requestUrl = GetRequestUrl $jobName
    $requestAuth = GetRequestAuth
    $requestHeaders = @{
        'Authorization' = ("Basic {0}" -f $requestAuth)
    }

    $response = Invoke-WebRequest -Uri $requestUrl -Headers $requestHeaders -Method Get -UseBasicParsing
    if ($response.StatusCode -ne 200) {
        throw "Packages Migration: Get webjob failed. $response"
    }

    return $response | ConvertFrom-Json
}

function GetJobState($jobName) {
    $model = GetJobModel $jobName

    if (!$model.latest_run) {
        return 'Ready'
    } elseif ($model.latest_run.end_time -lt $model.latest_run.start_time) {
        return 'Running'
    } elseif ($model.latest_run.status -eq 'Success') {
        return 'Success'
    } else {
        return 'Failed'
    }
}

function GetJobResultStatus($jobName) {
    $model = GetJobModel $jobName
    return $model.latest_run.status
}

function GetJobResultOutput($jobName) {
    $model = GetJobModel $jobName
    $requestUrl = $model.latest_run.output_url
    $requestAuth = GetRequestAuth
    $requestHeaders = @{
        'Authorization' = ("Basic {0}" -f $requestAuth)
    }

    $response = Invoke-WebRequest -Uri $requestUrl -Headers $requestHeaders -Method Get -UseBasicParsing
    if ($response.StatusCode -ne 200) {
        throw "Packages Migration: Get webjob output failed. $response"
    }

    return $response
}

function DeleteJob($jobName) {
    $requestUrl = GetRequestUrl $jobName
    $requestAuth = GetRequestAuth
    $requestHeaders = @{
        'Authorization' = ("Basic {0}" -f $requestAuth)
    }

    $response = Invoke-WebRequest -Uri $requestUrl -Headers $requestHeaders -Method Delete -UseBasicParsing
    if ($response.StatusCode -ne 200) {
        throw "Packages Migration: Start webjob failed. $response"
    }
}

function DeployAndRunJob($jobName, $jobFile) {
    UploadJob $jobName $jobFile
    StartJob $jobName

    $state = GetJobState $jobName
    while ($state -eq 'Ready' -or $state -eq 'Running') {
        Start-Sleep -Seconds 1

        $newState = GetJobState $jobName
        if ($state -ne $newState) {
            $state = $newState
            Write-Host("$state...")
        }
    }

    $resultStatus = GetJobResultStatus $jobName
    if ($resultStatus -eq 'Success') {
        if ($unattended) {
            Write-Host "WebJob $jobName has completed successfully."
        } else {
            Read-Host -Prompt "WebJob $jobName has completed successfully. Press any key to view the result."
        }
    } else {
        if ($unattended) {
            throw "WebJob $jobName has failed with status $resultStatus."
        } else {
            Read-Host -Prompt "WebJob $jobName has failed. Press any key to view the result."
        }
    }

    $output = GetJobResultOutput $jobName
    Write-Host $output
}

function Start-PackagesMigration {
    UploadMigrator

    $now = (Get-Date -Format 'yyyyMMddhhmmssfff')
    $workers = 1

    $startJobName = "PackagesMigrationStart_$now"

    $jobFilePath = [System.IO.Path]::GetTempPath()
    $jobFile = New-Item -Path (Join-Path $jobFilePath "run.cmd") -Force
    Add-Content $jobFile """%WEBROOT_PATH%\PackagesMigration\UiPath.Orchestrator.Setup.PackagesMigration.Console.exe"" start^"
    Add-Content $jobFile " --application-path ""%WEBROOT_PATH%""^"
    Add-Content $jobFile " --connection-string ""$connectionString""^"
    Add-Content $jobFile " --storage-type ""$storageType""^"
    Add-Content $jobFile " --storage-location ""$storageLocation""^"
    Add-Content $jobFile " --libraries-path ""$librariesPath""^"
    Add-Content $jobFile " --processes-path ""$processesPath""^"
    Add-Content $jobFile " --instance-key ""$instanceKey""^"
    Add-Content $jobFile " --workers $workers"

    DeployAndRunJob $startJobName $jobFile

    Read-Host -Prompt "Press any key to continue or CTRL+C to quit."

    # DeleteJob $startJobName
}

function Finalize-PackagesMigration {
    UploadMigrator

    $now = (Get-Date -Format 'yyyyMMddhhmmssfff')
    $finishJobName = "PackagesMigrationFinish_$now"

    $jobFilePath = [System.IO.Path]::GetTempPath()
    $jobFile = New-Item -Path (Join-Path $jobFilePath "run.cmd") -Force
    Add-Content $jobFile """%WEBROOT_PATH%\PackagesMigration\UiPath.Orchestrator.Setup.PackagesMigration.Console.exe"" finish^"
    Add-Content $jobFile " --connection-string ""$connectionString"""
    DeployAndRunJob $finishJobName $jobFile

    # DeleteJob $finishJobName
}
