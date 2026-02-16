#!/bin/zsh

# Setup Oh My Zsh (zsh-specific)
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)
source $ZSH/oh-my-zsh.sh
RPROMPT="[%D{%H:%M:%S}]"
