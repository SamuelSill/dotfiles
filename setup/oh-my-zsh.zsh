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

# Tick the clock in the prompt once a second while idle.
TMOUT=1
TRAPALRM() {
    (( prompt_clock_paused )) && return
    zle reset-prompt

    [[ -n $__searching ]] && __searching=$LASTWIDGET
}

typeset -g prompt_clock_paused=0

# The timer also fires while a widget is shelling out, where reset-prompt
# restores the line editor to its pre-widget state and discards whatever the
# widget inserted. Widgets that shell out (fzf) run through this instead.
run_widget_with_prompt_clock_paused() {
    local widget="$1"
    shift

    prompt_clock_paused=1
    "$widget" "$@"
    prompt_clock_paused=0
}
