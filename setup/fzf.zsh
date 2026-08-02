# fzf shell integration (Ctrl-R history search, Ctrl-T files, Alt-C cd).
# macOS/brew installs write ~/.fzf.zsh; Linux distros ship key-bindings under
# a system path instead, so fall back to the first one we find.
if [ -f ~/.fzf.zsh ]; then
    source ~/.fzf.zsh
elif (( $+commands[fzf] )); then
    # Newer fzf can emit the integration itself; older/distro builds ship files.
    if fzf --zsh >/dev/null 2>&1; then
        source <(fzf --zsh)
    else
        for _kb in \
            /usr/share/fzf/shell/key-bindings.zsh \
            /usr/share/doc/fzf/examples/key-bindings.zsh \
            /usr/share/zsh/site-functions/key-bindings.zsh \
            /etc/profile.d/fzf.zsh; do
            [ -f "$_kb" ] && source "$_kb" && break
        done
        unset _kb
    fi
fi

for _widget in fzf-history-widget fzf-file-widget fzf-cd-widget; do
    (( $+functions[$_widget] )) || continue

    functions[$_widget-keep-buffer]="run_widget_with_prompt_clock_paused $_widget"
    zle -N $_widget $_widget-keep-buffer
done
unset _widget
