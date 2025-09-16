function run-until-success {
    param(
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$Command
    )

    do {
        & $Command
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-Host "Command failed with exit code $exitCode, retrying..."
            Start-Sleep -Seconds 1
        }
    } while ($exitCode -ne 0)

    Write-Host "Command succeeded!"
}
