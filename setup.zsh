#!/bin/zsh

DOTFILES_DIR="${0:A:h}"
export DOTFILES_DIR

source "$DOTFILES_DIR/setup/oh-my-zsh.zsh"
source "$DOTFILES_DIR/setup/pyenv.zsh"
source "$DOTFILES_DIR/setup/fzf.zsh"
source "$DOTFILES_DIR/setup/aliases.zsh"
source "$DOTFILES_DIR/setup/functions.zsh"
source "$DOTFILES_DIR/setup/keybindings.zsh"
source "$DOTFILES_DIR/setup/zellij.zsh"

