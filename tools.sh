#!/bin/sh

# Note: This file contains shell-agnostic configurations.
# It detects the current shell and sources appropriate configs.

# Set DOTFILES_DIR
if [ -n "$BASH_VERSION" ]; then
    DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    DOTFILES_DIR="${0:A:h}"
else
    DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
export DOTFILES_DIR

# Detect current shell
current_shell=$(basename "$SHELL")

# Setup pyenv
export PYENV_ROOT="$HOME/.pyenv"
if [ -d "$PYENV_ROOT/bin" ]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
fi

case "$current_shell" in
    zsh)
        eval "$(pyenv init - zsh)"
        eval "$(pyenv virtualenv-init - zsh)"
        ;;
    bash)
        eval "$(pyenv init - bash)"
        eval "$(pyenv virtualenv-init - bash)"
        ;;
    *)
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)"
        ;;
esac

# Setup fzf if available (shell-specific)
case "$current_shell" in
    zsh)
        [ -f ~/.fzf.zsh ] && . ~/.fzf.zsh
        ;;
    bash)
        [ -f ~/.fzf.bash ] && . ~/.fzf.bash
        ;;
esac

# Setup gh-copilot (detect shell)
if command -v gh >/dev/null 2>&1; then
    case "$current_shell" in
        zsh)
            eval "$(gh copilot alias -- zsh)"
            ;;
        bash)
            eval "$(gh copilot alias -- bash)"
            ;;
    esac
fi

cp -r $DOTFILES_DIR/.config ~/.config/
