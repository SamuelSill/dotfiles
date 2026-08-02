export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)
source "$ZSH/oh-my-zsh.sh"

PROMPT='%{$fg[yellow]%}[%*]%{$reset_color%} %{$fg_bold[cyan]%}%c%{$reset_color%}$(git_prompt_info)
%(?:%{$fg_bold[green]%}❯%{$reset_color%} :%{$fg_bold[red]%}❯%{$reset_color%} )'
RPROMPT=""

ZSH_THEME_GIT_PROMPT_PREFIX=" (%{$fg[magenta]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%})"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[yellow]%}✗%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""

TMOUT=1
TRAPALRM() { zle reset-prompt }
