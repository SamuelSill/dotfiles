$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

try {
    $aliasCommands = & python3 "$ScriptDir/load_aliases.py" powershell "$ScriptDir"
    if ($LASTEXITCODE -eq 0) {
        Invoke-Expression $aliasCommands
    }
} catch {
    Write-Warning "Error loading aliases: $_"
}
