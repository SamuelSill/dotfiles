#!/bin/zsh
#
# --- Location (self-locating; :A resolves the stow/symlink to the real path) ---
DOTFILES_DIR="${0:A:h}"
export DOTFILES_DIR

# --- Oh My Zsh ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)
source "$ZSH/oh-my-zsh.sh"
RPROMPT="[%D{%H:%M:%S}]"

# --- pyenv (+ virtualenv) ---
export PYENV_ROOT="$HOME/.pyenv"
[ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init - zsh)"
    eval "$(pyenv virtualenv-init - zsh)"
fi

# --- fzf key bindings ---
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --- Alias library (git-utils helpers etc. defined in aliases.json) ---
eval "$(python3 "$DOTFILES_DIR/load_aliases.py" sh "$DOTFILES_DIR/aliases.json")"

# Open a URL in the OS default browser. Works on macOS, Linux, and WSL.
_open_url() {
  local url=$1
  case "$OSTYPE" in
    darwin*)        open "$url" ;;                 # macOS
    *)                                             # Linux / WSL / BSD
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url"
      elif command -v explorer.exe >/dev/null 2>&1; then   # WSL without xdg-open
        explorer.exe "$url"
      else
        print -u2 "mdview: open this in your browser -> $url"
      fi ;;
  esac >/dev/null 2>&1
}

# mdview - View a Markdown file in the browser.
mdview() {
  emulate -L zsh
  local file=$1
  [[ -n $file ]] || { print -u2 "usage: mdview <file.md>"; return 1 }
  [[ -f $file ]] || { print -u2 "mdview: no such file: $file"; return 1 }

  local dir=${MDVIEW_DIR:-$HOME/.cache/md-preview}
  local port=${MDVIEW_PORT:-8642}
  local abs=${file:A} base=${file:t}
  mkdir -p $dir
  # Prefer a symlink (edits live-reload); fall back to a copy if symlinks fail.
  ln -sf "$abs" "$dir/$base" 2>/dev/null || cp -f "$abs" "$dir/$base"

  # Start the server only if nothing is already answering on the port.
  if ! curl -sf -o /dev/null "http://localhost:$port/" 2>/dev/null; then
    ( cd $dir && nohup npx --yes markserv --port $port . >$dir/.markserv.log 2>&1 & )
    local i=0
    while ! curl -sf -o /dev/null "http://localhost:$port/" 2>/dev/null && (( i++ < 40 )); do
      sleep 0.25
    done
  fi

  local url="http://localhost:$port/$base"
  print "mdview: $url"
  _open_url "$url"
}

# mdview-stop — stop the markdown preview server (macOS / Linux / WSL).
mdview-stop() {
  emulate -L zsh
  local port=${MDVIEW_PORT:-8642}
  local pid
  pid=$(lsof -ti "tcp:$port" 2>/dev/null)
  [[ -n $pid ]] && { kill $pid && print "mdview: stopped ($pid)" } || print "mdview: not running"
}

# clip <file> — put a file on the clipboard so you can paste it.
# Behaviour depends on the file type, because that's what pasting apps actually
# consume:
#   * image  -> copies the raw image data, so Slack/etc. inline it on paste
#   * other  -> copies the file's TEXT contents (paste as a text block)
# Add -f to instead copy a file reference (text/uri-list) for file managers that
# accept a pasted file — but note Slack on Linux does NOT reliably attach a file
# from a clipboard paste; drag-drop / the attach button is the way for binaries.
# Cross-platform: Wayland (wl-copy), X11 (xclip), macOS (pbcopy / osascript).
clip() {
  emulate -L zsh
  local as_file=0
  [[ $1 == -f ]] && { as_file=1; shift; }
  local file=$1
  [[ -n $file && -f $file ]] || { print -u2 "usage: clip [-f] <file>"; return 1; }
  local abs=${file:A} mime
  mime=$(file -b --mime-type -- "$abs" 2>/dev/null)

  case "$OSTYPE" in
    darwin*)
      if (( as_file )); then
        osascript -e "set the clipboard to POSIX file \"$abs\"" \
          && print "clip: copied file reference — $file:t"
      elif [[ $mime == image/* ]]; then
        # AppleScript only reliably handles PNG image data on the clipboard.
        osascript -e "set the clipboard to (read (POSIX file \"$abs\") as «class PNGf»)" \
          && print "clip: copied image — paste into Slack" \
          || print -u2 "clip: macOS image copy works best with PNG"
      else
        pbcopy < "$abs" && print "clip: copied text contents of $file:t"
      fi
      ;;
    *)
      local tool
      if   command -v wl-copy >/dev/null 2>&1; then tool=wl
      elif command -v xclip   >/dev/null 2>&1; then tool=x
      else print -u2 "clip: need wl-copy or xclip on Linux"; return 1; fi

      if (( as_file )); then
        local uri="file://$abs"
        if [[ $tool == wl ]]; then printf '%s\r\n' "$uri" | wl-copy --type text/uri-list
        else printf '%s\r\n' "$uri" | xclip -selection clipboard -t text/uri-list; fi
        print "clip: copied file reference ($uri)"
        print "clip: note — Slack may not attach this on paste; use drag-drop for binaries"
      elif [[ $mime == image/* ]]; then
        if [[ $tool == wl ]]; then wl-copy --type "$mime" < "$abs"
        else xclip -selection clipboard -t "$mime" -i "$abs"; fi
        print "clip: copied image ($mime) — paste into Slack"
      else
        if [[ $tool == wl ]]; then wl-copy < "$abs"
        else xclip -selection clipboard -i "$abs"; fi
        print "clip: copied text contents of $file:t"
      fi
      ;;
  esac
}

# Ctrl-Backspace deletes the previous word (many terminals send ^H for it).
bindkey '^H' backward-kill-word

# Auto-start zellij in interactive shells (unless already inside a session).
if [[ -z "$ZELLIJ" ]] && [[ -o interactive ]]; then
  zellij
fi
