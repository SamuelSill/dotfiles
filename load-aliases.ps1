$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

try {
    $aliasCommands = & python3 "$SCRIPT_DIR/load_aliases.py" powershell "$SCRIPT_DIR/aliases.json"
    if ($LASTEXITCODE -eq 0) {
        Invoke-Expression $aliasCommands
    }
} catch {
    Write-Warning "Error loading aliases: $_"
}
