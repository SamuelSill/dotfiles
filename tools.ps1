$Global:DOTFILES_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:DOTFILES_DIR = $DOTFILES_DIR

# Setup pyenv
$env:PYENV_ROOT = "$HOME/.pyenv"
if (Test-Path "$env:PYENV_ROOT/bin") {
    $env:PATH = "$env:PYENV_ROOT/bin:$env:PATH"
}
