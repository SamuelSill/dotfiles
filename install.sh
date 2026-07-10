#!/usr/bin/env bash
#
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Logging helpers
################################################################################
c_step=$'\033[1;34m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_off=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_step" "$c_off" "$*"; }
ok()   { printf '  %sok%s   %s\n' "$c_ok"  "$c_off" "$*"; }
warn() { printf '  %swarn%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

################################################################################
# Detect platform + package manager
################################################################################
OS="$(uname -s)"
PM=""
case "$OS" in
  Darwin) PM=brew ;;
  Linux)
    if   have apt-get; then PM=apt
    elif have dnf;     then PM=dnf
    elif have pacman;  then PM=pacman
    else die "No supported Linux package manager found (need apt, dnf, or pacman)."; fi ;;
  *) die "Unsupported OS '$OS'. On Windows run install.ps1." ;;
esac

# Non-Homebrew managers need root for installs; use sudo when we are not root.
SUDO=""
if [ "$PM" != brew ] && [ "$(id -u)" -ne 0 ]; then
  have sudo || die "Need root to install packages but 'sudo' is not available."
  SUDO=sudo
fi

step "Platform: $OS   package manager: $PM"

################################################################################
# Package-manager primitives
################################################################################
ensure_brew() {
  have brew && return 0
  step "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew   ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  have brew || die "Homebrew install did not put 'brew' on PATH."
}

pm_refresh() {
  case "$PM" in
    brew)   ensure_brew ;;
    apt)    $SUDO apt-get update -y ;;
    dnf)    : ;;                                  # dnf refreshes metadata itself
    pacman) $SUDO pacman -Sy --noconfirm ;;
  esac
}

# pm_install <space-separated packages> — install for the active manager.
pm_install() {
  case "$PM" in
    brew)   brew install $* ;;
    apt)    $SUDO apt-get install -y $* ;;
    dnf)    $SUDO dnf install -y $* ;;
    pacman) $SUDO pacman -S --needed --noconfirm $* ;;
  esac
}

# need <cmd> <brew-pkg> <apt-pkg> <dnf-pkg> <pacman-pkg>
# Install only if <cmd> is missing. Use "-" for a manager that has no package
# (the caller is then expected to provide a fallback).
need() {
  local cmd="$1" brewp="$2" aptp="$3" dnfp="$4" pacp="$5" sel=""
  if have "$cmd"; then ok "$cmd"; return 0; fi
  case "$PM" in brew) sel="$brewp" ;; apt) sel="$aptp" ;; dnf) sel="$dnfp" ;; pacman) sel="$pacp" ;; esac
  if [ "$sel" = "-" ]; then return 3; fi   # no package on this manager
  step "Installing $cmd ($sel)"
  pm_install $sel
}

################################################################################
# 1. Core tools available directly from every package manager
################################################################################
core_tools() {
  pm_refresh
  need git    git      git      git      git
  need curl   curl     curl     curl     curl
  need zsh    zsh      zsh      zsh      zsh
  need nvim   neovim   neovim   neovim   neovim
  need rg     ripgrep  ripgrep  ripgrep  ripgrep
  need jq     jq       jq       jq       jq
  need lazygit lazygit lazygit  lazygit  lazygit
  need delta  git-delta git-delta git-delta git-delta
  need fzf    fzf      fzf      fzf      fzf
  need stow   stow     stow     stow     stow    # GNU stow: symlinks .config into ~

  # Node + npm (mdview/markserv, the tree-sitter CLI fallback, Claude Code CLI).
  if have npm; then ok "npm"; else
    step "Installing node/npm"
    case "$PM" in
      brew)   pm_install node ;;
      apt)    pm_install nodejs npm ;;
      dnf)    pm_install nodejs npm ;;
      pacman) pm_install nodejs npm ;;
    esac
  fi

  # C toolchain + make (tree-sitter parser builds, and other `make`-built plugins).
  if have cc || have gcc || have clang; then ok "C compiler"; else
    step "Installing a C toolchain"
    case "$PM" in
      brew)   xcode-select --install 2>/dev/null || ok "Xcode CLT already requested" ;;
      apt)    pm_install build-essential ;;
      dnf)    $SUDO dnf groupinstall -y "Development Tools" || pm_install gcc make ;;
      pacman) pm_install base-devel ;;
    esac
  fi
  have make || { step "Installing make"; case "$PM" in brew) : ;; *) pm_install make ;; esac; }

  # Terminal + multiplexer. zellij/kitty are unix-only; installed on both mac and
  # Linux. (Older Debian/Ubuntu may lack a zellij package — see fallback below.)
  need kitty  --cask\ kitty kitty kitty kitty || warn "kitty unavailable via $PM; install it manually if wanted"
  need zellij zellij   zellij   zellij   zellij || install_zellij_fallback

  # Wayland clipboard integration for zellij's copy_command (Linux only).
  if [ "$OS" = Linux ]; then
    need wl-copy - wl-clipboard wl-clipboard wl-clipboard || warn "wl-clipboard unavailable; zellij copy_command needs it under Wayland"
  fi
}

# Debian/Ubuntu often ship no zellij package; grab the official release binary.
install_zellij_fallback() {
  have zellij && return 0
  step "Installing zellij from upstream release"
  local arch; arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) warn "No zellij prebuilt for arch '$arch'; skip"; return 0 ;;
  esac
  local url="https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/z.tar.gz" && tar -xzf "$tmp/z.tar.gz" -C "$tmp"; then
    $SUDO install -m755 "$tmp/zellij" /usr/local/bin/zellij && ok "zellij -> /usr/local/bin"
  else
    warn "zellij download failed; install it manually"
  fi
  rm -rf "$tmp"
}

################################################################################
# 2. Tools whose command name differs from the package, or need a shim
################################################################################
# fd: Debian names the binary 'fdfind'; fzf-lua calls 'fd'. Install the package,
# then make sure a 'fd' exists on a PATH dir.
setup_fd() {
  if have fd; then ok "fd"; return 0; fi
  step "Installing fd"
  case "$PM" in
    brew)   pm_install fd ;;
    apt)    pm_install fd-find ;;
    dnf)    pm_install fd-find ;;
    pacman) pm_install fd ;;
  esac
  have fd && { ok "fd"; return 0; }
  if have fdfind; then
    if [ -w /usr/local/bin ] || [ -n "$SUDO" ]; then
      $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd && ok "linked fdfind -> /usr/local/bin/fd"
    else
      mkdir -p "$HOME/.local/bin"; ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
      warn "linked fdfind -> ~/.local/bin/fd (ensure ~/.local/bin is on PATH)"
    fi
  fi
}

# clangd: the general nvim config configures clangd as the C/C++ LSP.
setup_clangd() {
  have clangd && { ok "clangd"; return 0; }
  step "Installing clangd"
  case "$PM" in
    brew)   pm_install llvm
            ln -sf "$(brew --prefix llvm)/bin/clangd" "$(brew --prefix)/bin/clangd" 2>/dev/null || true ;;
    apt)    pm_install clangd || pm_install clang-tools ;;
    dnf)    pm_install clang-tools-extra ;;
    pacman) pm_install clang ;;
  esac
  have clangd || warn "clangd not on PATH; C/C++ LSP will be inactive until it is"
}

# tree-sitter CLI: needed by the nvim treesitter 'main' branch to build parsers.
setup_tree_sitter() {
  have tree-sitter && { ok "tree-sitter"; return 0; }
  step "Installing tree-sitter CLI"
  case "$PM" in
    brew)   pm_install tree-sitter ;;
    pacman) pm_install tree-sitter-cli ;;
    *)      if have npm; then $SUDO npm install -g tree-sitter-cli || npm install -g tree-sitter-cli
            else warn "cannot install tree-sitter (no npm)"; fi ;;
  esac
}

################################################################################
# 3. Bootstrap installs that are not plain packages
################################################################################
# pyenv + pyenv-virtualenv (setup.zsh runs `pyenv init` / `pyenv virtualenv-init`).
setup_pyenv() {
  if [ -d "$HOME/.pyenv" ] || have pyenv; then ok "pyenv"; else
    step "Installing pyenv"
    if [ "$PM" = brew ]; then pm_install pyenv pyenv-virtualenv
    else curl -fsSL https://pyenv.run | bash; fi
  fi
  # pyenv-virtualenv as a plugin when pyenv came from the pyenv.run installer.
  if [ "$PM" != brew ] && [ ! -d "$HOME/.pyenv/plugins/pyenv-virtualenv" ] && [ -d "$HOME/.pyenv" ]; then
    git clone --depth 1 https://github.com/pyenv/pyenv-virtualenv.git \
      "$HOME/.pyenv/plugins/pyenv-virtualenv" 2>/dev/null || warn "pyenv-virtualenv clone failed"
  fi
  # Python build prerequisites (so `pyenv install <x>` can compile CPython).
  step "Installing Python build prerequisites"
  case "$PM" in
    brew)   pm_install openssl readline sqlite3 xz zlib tcl-tk || true ;;
    apt)    pm_install make build-essential libssl-dev zlib1g-dev libbz2-dev \
              libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
              libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev || true ;;
    dnf)    pm_install make gcc zlib-devel bzip2 bzip2-devel readline-devel \
              sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel || true ;;
    pacman) pm_install base-devel openssl zlib xz tk || true ;;
  esac
}

# Oh My Zsh + the two plugins setup.zsh enables.
setup_omz() {
  if [ -d "$HOME/.oh-my-zsh" ]; then ok "oh-my-zsh"; else
    step "Installing Oh My Zsh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local p
  for p in zsh-syntax-highlighting zsh-autosuggestions; do
    if [ -d "$custom/plugins/$p" ]; then ok "plugin $p"; else
      step "Installing zsh plugin $p"
      git clone --depth 1 "https://github.com/zsh-users/$p.git" "$custom/plugins/$p"
    fi
  done
}

# fzf shell key-bindings (setup.zsh sources ~/.fzf.zsh if present).
setup_fzf_keybindings() {
  [ -f "$HOME/.fzf.zsh" ] && { ok "fzf key-bindings"; return 0; }
  if [ "$PM" = brew ] && [ -x "$(brew --prefix)/opt/fzf/install" ]; then
    step "Setting up fzf key-bindings"
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null
  else
    warn "fzf key-bindings file not created; run the fzf 'install' script if you want Ctrl-R/Ctrl-T bindings"
  fi
}

# GitPython — imported by the git-utils scripts (run under the system python3).
setup_python_deps() {
  step "Installing Python deps (GitPython)"
  local req="$DOTFILES_DIR/git-utils/requirements.txt"
  [ -f "$req" ] || { warn "no git-utils/requirements.txt; skipping"; return 0; }
  python3 -m pip install --user -r "$req" 2>/dev/null \
    || python3 -m pip install --user --break-system-packages -r "$req" \
    || warn "pip install failed; install GitPython manually for the git-utils aliases"
}

# Claude Code CLI — the `claude` alias launches it via run_claude.py.
setup_claude() {
  [ -n "${SKIP_CLAUDE:-}" ] && { warn "SKIP_CLAUDE set; skipping Claude Code CLI"; return 0; }
  have claude && { ok "claude"; return 0; }
  if have npm; then
    step "Installing Claude Code CLI"
    $SUDO npm install -g @anthropic-ai/claude-code 2>/dev/null \
      || npm install -g @anthropic-ai/claude-code \
      || warn "Claude Code CLI install failed; see https://claude.com/claude-code"
  else
    warn "npm missing; cannot install Claude Code CLI"
  fi
}

# A Nerd Font so kitty + zellij's status-bar glyphs render (kitty.conf note).
setup_font() {
  [ -n "${SKIP_FONT:-}" ] && { warn "SKIP_FONT set; skipping Nerd Font"; return 0; }
  if [ "$PM" = brew ]; then
    step "Installing JetBrainsMono Nerd Font"
    brew install --cask font-jetbrains-mono-nerd-font font-source-code-pro 2>/dev/null || warn "font cask install failed"
    return 0
  fi
  local dir="$HOME/.local/share/fonts"
  if ls "$dir"/JetBrainsMono*Nerd* >/dev/null 2>&1; then ok "Nerd Font"; return 0; fi
  step "Installing JetBrainsMono Nerd Font"
  have unzip || pm_install unzip || { warn "need unzip for the font download"; return 0; }
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$tmp/f.zip"; then
    mkdir -p "$dir"; unzip -qo "$tmp/f.zip" -d "$dir"; have fc-cache && fc-cache -f "$dir" >/dev/null 2>&1
    ok "Nerd Font installed to $dir"
  else
    warn "Nerd Font download failed"
  fi
  rm -rf "$tmp"
}

################################################################################
# Deployment: stow config into $HOME + wire up the shell hook
################################################################################
# deploy_pkg <repo_dir> <package> — symlink stow/<package> into $HOME (idempotent).
# Any real (non-symlink) file that would collide is backed up first.
deploy_pkg() {
  have stow || { warn "stow not installed; skipping '$2' symlinks"; return 0; }
  local repo="$1" pkg="$2" stowdir="$1/stow" pkg_dir="$1/stow/$2"
  [ -d "$pkg_dir" ] || { warn "no stow package '$pkg' at $pkg_dir"; return 0; }
  local backup; backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
  ( cd "$pkg_dir" && find . -type f ) | sed 's|^\./||' | while IFS= read -r rel; do
    local tgt="$HOME/$rel"
    if [ -e "$tgt" ] && [ ! -L "$tgt" ]; then
      mkdir -p "$backup/$(dirname "$rel")"; mv "$tgt" "$backup/$rel"
      warn "backed up existing $rel -> $backup/$rel"
    fi
  done
  if stow --no-folding --restow --target "$HOME" --dir "$stowdir" "$pkg"; then
    ok "stowed $pkg"
  else
    warn "stow $pkg failed"
  fi
}

# ensure_hook <entry_script_abspath> — idempotent guarded `source` line in ~/.zshrc.
ensure_hook() {
  local rc="${ZDOTDIR:-$HOME}/.zshrc"; touch "$rc"
  if grep -qF "$1" "$rc"; then ok "shell hook already present in $rc"; return 0; fi
  printf '\n# >>> dotfiles hook >>>\nsource %s\n# <<< dotfiles hook <<<\n' "$1" >> "$rc"
  ok "added shell hook to $rc"
}

################################################################################
# Run
################################################################################
core_tools
setup_fd
setup_clangd
setup_tree_sitter
setup_pyenv
setup_omz
setup_fzf_keybindings
setup_python_deps
setup_claude
setup_font

step "Deploying config via stow"
deploy_pkg "$DOTFILES_DIR" config

# When chained from a wrapper repo the wrapper owns the
# ~/.zshrc hook (it sources this library itself). Standalone, we add it here.
if [ -n "${DOTFILES_SKIP_SHELL:-}" ]; then
  warn "DOTFILES_SKIP_SHELL set; leaving ~/.zshrc hook to the wrapper installer"
else
  step "Wiring up the shell hook"
  ensure_hook "$DOTFILES_DIR/setup.zsh"
fi

step "Done."
cat <<'EOF'

Next steps:
  * Make zsh your login shell if it isn't:   chsh -s "$(command -v zsh)"
  * Open a new terminal (or `source ~/.zshrc`) so the config, aliases and PATH load.
  * Neovim installs its plugins on first launch (lazy.nvim); open `nvim` once
    and let it finish, then run :checkhealth to verify treesitter/LSP tooling.
EOF
