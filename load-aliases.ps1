try {
    $aliasCommands = & python3 "$DOTFILES_DIR/load_aliases.py" powershell "$DOTFILES_DIR/aliases.json"
    if ($LASTEXITCODE -eq 0) {
        Invoke-Expression $aliasCommands
    }
} catch {
    Write-Warning "Error loading aliases: $_"
}
