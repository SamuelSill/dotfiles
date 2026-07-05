#!/bin/zsh

# Setup Oh My Zsh (zsh-specific)
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)
source $ZSH/oh-my-zsh.sh
RPROMPT="[%D{%H:%M:%S}]"

# Open a URL in the OS default browser. Works wherever zsh runs: macOS, Linux,
# WSL, and Windows under MSYS2/Git-Bash/Cygwin.
_open_url() {
  local url=$1
  case "$OSTYPE" in
    darwin*)        open "$url" ;;                 # macOS
    cygwin*|msys*)  explorer.exe "$url" ;;         # Windows (MSYS2 / Git Bash / Cygwin)
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

# mdview <file.md> — preview a markdown file (GitHub-styled, live-reload) in the browser.
# Uses markserv over a small scoped dir (~/.cache/md-preview) so its file watcher
# never tries to recurse a huge tree like the Chromium checkout (that hits ENOSPC).
# Cross-platform: macOS, Linux, and Windows (run under MSYS2/Git-Bash/Cygwin zsh).
mdview() {
  emulate -L zsh
  local file=$1
  [[ -n $file ]] || { print -u2 "usage: mdview <file.md>"; return 1 }
  [[ -f $file ]] || { print -u2 "mdview: no such file: $file"; return 1 }

  local dir=${MDVIEW_DIR:-$HOME/.cache/md-preview}
  local port=${MDVIEW_PORT:-8642}
  local abs=${file:A} base=${file:t}
  mkdir -p $dir
  # Prefer a symlink (edits live-reload); fall back to a copy where symlinks
  # aren't permitted (e.g. Windows without Developer Mode) so preview still works.
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

# mdview-stop — stop the markdown preview server (cross-platform).
mdview-stop() {
  emulate -L zsh
  local port=${MDVIEW_PORT:-8642}
  local pid
  case "$OSTYPE" in
    cygwin*|msys*)
      # Windows: find the LISTENING pid on the port via netstat, then taskkill.
      pid=$(netstat -ano 2>/dev/null | awk -v p=":$port" '$0 ~ p && /LISTENING/ {print $NF; exit}')
      [[ -n $pid ]] && taskkill //PID "$pid" //F >/dev/null 2>&1 \
        && print "mdview: stopped ($pid)" || print "mdview: not running"
      ;;
    *)
      pid=$(lsof -ti "tcp:$port" 2>/dev/null)
      [[ -n $pid ]] && { kill $pid && print "mdview: stopped ($pid)" } || print "mdview: not running"
      ;;
  esac
}
