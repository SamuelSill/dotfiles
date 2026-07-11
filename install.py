#!/usr/bin/env python3
import datetime
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DOTFILES_DIR = Path(__file__).resolve().parent

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
_STEP, _OK, _WARN, _ERR, _OFF = "\033[1;34m", "\033[32m", "\033[33m", "\033[31m", "\033[0m"


def step(msg): print(f"\n{_STEP}==>{_OFF} {msg}")
def ok(msg):   print(f"  {_OK}ok{_OFF}   {msg}")
def warn(msg): print(f"  {_WARN}warn{_OFF} {msg}", file=sys.stderr)
def die(msg):  print(f"{_ERR}error{_OFF} {msg}", file=sys.stderr); sys.exit(1)
def have(cmd): return shutil.which(cmd) is not None


# --------------------------------------------------------------------------- #
# Platform + package manager (detected lazily so importing is side-effect free)
# --------------------------------------------------------------------------- #
OS = platform.system()  # "Darwin" or "Linux"
_PM = None


def pkg_manager():
    global _PM
    if _PM:
        return _PM
    if OS == "Darwin":
        _PM = "brew"
    elif OS == "Linux":
        if have("apt-get"):
            _PM = "apt"
        elif have("dnf"):
            _PM = "dnf"
        elif have("pacman"):
            _PM = "pacman"
        else:
            die("No supported Linux package manager found (need apt, dnf, or pacman).")
    else:
        die(f"Unsupported OS '{OS}'. On Windows use WSL.")
    return _PM


def sudo_prefix():
    """['sudo'] when a non-brew install needs root, else []."""
    if pkg_manager() == "brew" or os.geteuid() == 0:
        return []
    if not have("sudo"):
        die("Need root to install packages but 'sudo' is not available.")
    return ["sudo"]


def run(cmd, *, check=False, quiet=False, shell=False, env=None):
    """Thin subprocess wrapper. `cmd` is a list (or a string when shell=True)."""
    devnull = subprocess.DEVNULL if quiet else None
    return subprocess.run(cmd, check=check, shell=shell, env=env,
                          stdout=devnull, stderr=devnull)


def _out(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def ensure_brew():
    if have("brew"):
        return
    step("Installing Homebrew")
    run('/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"',
        shell=True)
    for cand in ("/opt/homebrew/bin", "/usr/local/bin"):
        if Path(cand, "brew").exists():
            os.environ["PATH"] = f"{cand}:{os.environ['PATH']}"
    if not have("brew"):
        die("Homebrew install did not put 'brew' on PATH.")


def pm_refresh():
    pm = pkg_manager()
    if pm == "brew":
        ensure_brew()
    elif pm == "apt":
        run(sudo_prefix() + ["apt-get", "update", "-y"])
    elif pm == "pacman":
        run(sudo_prefix() + ["pacman", "-Sy", "--noconfirm"])
    # dnf refreshes metadata itself


def pm_install(pkgs):
    """Install space-separated <pkgs> with the active manager. Returns True on success."""
    toks = pkgs.split() if isinstance(pkgs, str) else list(pkgs)
    pm = pkg_manager()
    if pm == "brew":
        cmd = ["brew", "install", *toks]
    elif pm == "apt":
        cmd = sudo_prefix() + ["apt-get", "install", "-y", *toks]
    elif pm == "dnf":
        cmd = sudo_prefix() + ["dnf", "install", "-y", *toks]
    elif pm == "pacman":
        cmd = sudo_prefix() + ["pacman", "-S", "--needed", "--noconfirm", *toks]
    return run(cmd).returncode == 0


def need(cmd, brew, apt, dnf, pacman):
    """Install <cmd> only if missing. Use "-" for a manager that has no package.
    Returns True if present/installed, False if unavailable (so callers can fall back."""
    if have(cmd):
        ok(cmd)
        return True
    sel = {"brew": brew, "apt": apt, "dnf": dnf, "pacman": pacman}[pkg_manager()]
    if sel == "-":
        return False
    step(f"Installing {cmd} ({sel})")
    return pm_install(sel)


# --------------------------------------------------------------------------- #
# 1. Core tools available directly from every package manager
# --------------------------------------------------------------------------- #
def core_tools():
    pm_refresh()
    need("git", "git", "git", "git", "git")
    need("curl", "curl", "curl", "curl", "curl")
    need("zsh", "zsh", "zsh", "zsh", "zsh")
    need("nvim", "neovim", "neovim", "neovim", "neovim")
    need("rg", "ripgrep", "ripgrep", "ripgrep", "ripgrep")
    need("jq", "jq", "jq", "jq", "jq")
    need("lazygit", "lazygit", "lazygit", "lazygit", "lazygit")
    need("delta", "git-delta", "git-delta", "git-delta", "git-delta")
    need("fzf", "fzf", "fzf", "fzf", "fzf")
    need("stow", "stow", "stow", "stow", "stow")  # GNU stow: symlinks .config into ~

    # Node + npm (mdview/markserv, the tree-sitter CLI fallback, Claude Code CLI).
    if have("npm"):
        ok("npm")
    else:
        step("Installing node/npm")
        pm_install("node" if pkg_manager() == "brew" else "nodejs npm")

    # C toolchain + make (tree-sitter parser builds, make-built plugins).
    if have("cc") or have("gcc") or have("clang"):
        ok("C compiler")
    else:
        step("Installing a C toolchain")
        pm = pkg_manager()
        if pm == "brew":
            run("xcode-select --install", shell=True)
        elif pm == "apt":
            pm_install("build-essential")
        elif pm == "dnf":
            if not run(sudo_prefix() + ["dnf", "groupinstall", "-y", "Development Tools"]).returncode == 0:
                pm_install("gcc make")
        elif pm == "pacman":
            pm_install("base-devel")
    if not have("make") and pkg_manager() != "brew":
        step("Installing make")
        pm_install("make")

    # Terminal + multiplexer (unix-only; installed on mac and Linux).
    if not need("kitty", "--cask kitty", "kitty", "kitty", "kitty"):
        warn("kitty unavailable via the package manager; install it manually if wanted")
    if not need("zellij", "zellij", "zellij", "zellij", "zellij"):
        install_zellij_fallback()

    # Wayland clipboard integration for zellij's copy_command (Linux only).
    if OS == "Linux" and not need("wl-copy", "-", "wl-clipboard", "wl-clipboard", "wl-clipboard"):
        warn("wl-clipboard unavailable; zellij copy_command needs it under Wayland")


def install_zellij_fallback():
    """Debian/Ubuntu often ship no zellij package; grab the official release binary."""
    if have("zellij"):
        return
    step("Installing zellij from upstream release")
    arch = {"x86_64": "x86_64", "amd64": "x86_64",
            "aarch64": "aarch64", "arm64": "aarch64"}.get(platform.machine())
    if not arch:
        warn(f"No zellij prebuilt for arch '{platform.machine()}'; skip")
        return
    url = f"https://github.com/zellij-org/zellij/releases/latest/download/zellij-{arch}-unknown-linux-musl.tar.gz"
    tmp = tempfile.mkdtemp()
    tar = Path(tmp, "z.tar.gz")
    if (run(["curl", "-fsSL", url, "-o", str(tar)]).returncode == 0
            and run(["tar", "-xzf", str(tar), "-C", tmp]).returncode == 0):
        run(sudo_prefix() + ["install", "-m755", str(Path(tmp, "zellij")), "/usr/local/bin/zellij"])
        ok("zellij -> /usr/local/bin")
    else:
        warn("zellij download failed; install it manually")
    shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------- #
# 2. Tools whose command name differs from the package, or need a shim
# --------------------------------------------------------------------------- #
def setup_fd():
    """Debian names the binary 'fdfind'; fzf-lua calls 'fd'. Ensure a 'fd' on PATH."""
    if have("fd"):
        ok("fd")
        return
    step("Installing fd")
    pm_install({"brew": "fd", "apt": "fd-find", "dnf": "fd-find", "pacman": "fd"}[pkg_manager()])
    if have("fd"):
        ok("fd")
        return
    if have("fdfind"):
        src = shutil.which("fdfind")
        if os.access("/usr/local/bin", os.W_OK) or sudo_prefix():
            run(sudo_prefix() + ["ln", "-sf", src, "/usr/local/bin/fd"])
            ok("linked fdfind -> /usr/local/bin/fd")
        else:
            (Path.home() / ".local/bin").mkdir(parents=True, exist_ok=True)
            run(["ln", "-sf", src, str(Path.home() / ".local/bin/fd")])
            warn("linked fdfind -> ~/.local/bin/fd (ensure ~/.local/bin is on PATH)")


def setup_clangd():
    """The general nvim config configures clangd as the C/C++ LSP."""
    if have("clangd"):
        ok("clangd")
        return
    step("Installing clangd")
    pm = pkg_manager()
    if pm == "brew":
        pm_install("llvm")
        run(["ln", "-sf", f"{_out(['brew', '--prefix', 'llvm'])}/bin/clangd",
             f"{_out(['brew', '--prefix'])}/bin/clangd"])
    elif pm == "apt":
        pm_install("clangd") or pm_install("clang-tools")
    elif pm == "dnf":
        pm_install("clang-tools-extra")
    elif pm == "pacman":
        pm_install("clang")
    if not have("clangd"):
        warn("clangd not on PATH; C/C++ LSP will be inactive until it is")


def setup_tree_sitter():
    """tree-sitter CLI: the nvim treesitter 'main' branch builds parsers with it."""
    if have("tree-sitter"):
        ok("tree-sitter")
        return
    step("Installing tree-sitter CLI")
    pm = pkg_manager()
    if pm == "brew":
        pm_install("tree-sitter")
    elif pm == "pacman":
        pm_install("tree-sitter-cli")
    elif have("npm"):
        run(sudo_prefix() + ["npm", "install", "-g", "tree-sitter-cli"]) or \
            run(["npm", "install", "-g", "tree-sitter-cli"])
    else:
        warn("cannot install tree-sitter (no npm)")


def setup_pyenv():
    """pyenv + pyenv-virtualenv (setup.zsh runs `pyenv init` / `pyenv virtualenv-init`)."""
    if (Path.home() / ".pyenv").is_dir() or have("pyenv"):
        ok("pyenv")
    else:
        step("Installing pyenv")
        if pkg_manager() == "brew":
            pm_install("pyenv pyenv-virtualenv")
        else:
            run("curl -fsSL https://pyenv.run | bash", shell=True)
    plugin = Path.home() / ".pyenv/plugins/pyenv-virtualenv"
    if pkg_manager() != "brew" and not plugin.is_dir() and (Path.home() / ".pyenv").is_dir():
        if run(["git", "clone", "--depth", "1",
                "https://github.com/pyenv/pyenv-virtualenv.git", str(plugin)]).returncode != 0:
            warn("pyenv-virtualenv clone failed")
    step("Installing Python build prerequisites")
    prereqs = {
        "brew": "openssl readline sqlite3 xz zlib tcl-tk",
        "apt": ("make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev "
                "libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev "
                "libffi-dev liblzma-dev"),
        "dnf": ("make gcc zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel "
                "openssl-devel tk-devel libffi-devel xz-devel"),
        "pacman": "base-devel openssl zlib xz tk",
    }[pkg_manager()]
    pm_install(prereqs)


def setup_omz():
    """Oh My Zsh + the two plugins setup.zsh enables."""
    if (Path.home() / ".oh-my-zsh").is_dir():
        ok("oh-my-zsh")
    else:
        step("Installing Oh My Zsh")
        env = {**os.environ, "RUNZSH": "no", "CHSH": "no", "KEEP_ZSHRC": "yes"}
        run('sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"',
            shell=True, env=env)
    custom = Path(os.environ.get("ZSH_CUSTOM", str(Path.home() / ".oh-my-zsh/custom")))
    for p in ("zsh-syntax-highlighting", "zsh-autosuggestions"):
        if (custom / "plugins" / p).is_dir():
            ok(f"plugin {p}")
        else:
            step(f"Installing zsh plugin {p}")
            run(["git", "clone", "--depth", "1",
                 f"https://github.com/zsh-users/{p}.git", str(custom / "plugins" / p)])


def setup_fzf_keybindings():
    """fzf shell key-bindings (setup.zsh sources ~/.fzf.zsh if present)."""
    if (Path.home() / ".fzf.zsh").exists():
        ok("fzf key-bindings")
        return
    installer = Path(_out(["brew", "--prefix"]), "opt/fzf/install") if pkg_manager() == "brew" else None
    if installer and installer.is_file() and os.access(installer, os.X_OK):
        step("Setting up fzf key-bindings")
        run([str(installer), "--key-bindings", "--completion",
             "--no-update-rc", "--no-bash", "--no-fish"], quiet=True)
    else:
        warn("fzf key-bindings file not created; run the fzf 'install' script for Ctrl-R/Ctrl-T")


def setup_python_deps():
    """GitPython — imported by the git-utils scripts (run under the system python3)."""
    step("Installing Python deps (GitPython)")
    req = DOTFILES_DIR / "git-utils/requirements.txt"
    if not req.exists():
        warn("no git-utils/requirements.txt; skipping")
        return
    py = sys.executable or "python3"
    if run([py, "-m", "pip", "install", "--user", "-r", str(req)], quiet=True).returncode != 0 and \
       run([py, "-m", "pip", "install", "--user", "--break-system-packages", "-r", str(req)]).returncode != 0:
        warn("pip install failed; install GitPython manually for the git-utils aliases")


def setup_claude():
    """Claude Code CLI — the `claude` alias launches it via run_claude.py."""
    if os.environ.get("SKIP_CLAUDE"):
        warn("SKIP_CLAUDE set; skipping Claude Code CLI")
        return
    if have("claude"):
        ok("claude")
        return
    if not have("npm"):
        warn("npm missing; cannot install Claude Code CLI")
        return
    step("Installing Claude Code CLI")
    if run(sudo_prefix() + ["npm", "install", "-g", "@anthropic-ai/claude-code"]).returncode != 0 and \
       run(["npm", "install", "-g", "@anthropic-ai/claude-code"]).returncode != 0:
        warn("Claude Code CLI install failed; see https://claude.com/claude-code")


def setup_font():
    """A Nerd Font so kitty + zellij's status-bar glyphs render."""
    if os.environ.get("SKIP_FONT"):
        warn("SKIP_FONT set; skipping Nerd Font")
        return
    if pkg_manager() == "brew":
        step("Installing JetBrainsMono Nerd Font")
        if not run(["brew", "install", "--cask",
                    "font-jetbrains-mono-nerd-font", "font-source-code-pro"]).returncode == 0:
            warn("font cask install failed")
        return
    dest = Path.home() / ".local/share/fonts"
    if list(dest.glob("JetBrainsMono*Nerd*")):
        ok("Nerd Font")
        return
    step("Installing JetBrainsMono Nerd Font")
    if not have("unzip") and not pm_install("unzip"):
        warn("need unzip for the font download")
        return
    tmp = tempfile.mkdtemp()
    zip_path = Path(tmp, "f.zip")
    url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    if run(["curl", "-fsSL", url, "-o", str(zip_path)]).returncode == 0:
        dest.mkdir(parents=True, exist_ok=True)
        run(["unzip", "-qo", str(zip_path), "-d", str(dest)])
        if have("fc-cache"):
            run(["fc-cache", "-f", str(dest)], quiet=True)
        ok(f"Nerd Font installed to {dest}")
    else:
        warn("Nerd Font download failed")
    shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------- #
# Reusable deployment helpers (also called by wrapper installers)
# --------------------------------------------------------------------------- #
def deploy_pkg(repo_dir, package):
    """Symlink <repo_dir>/stow/<package> into $HOME with GNU stow (idempotent).
    Any real (non-symlink) file that would collide is backed up first."""
    if not have("stow"):
        warn(f"stow not installed; skipping '{package}' symlinks")
        return
    stowdir = Path(repo_dir) / "stow"
    pkg_dir = stowdir / package
    if not pkg_dir.is_dir():
        warn(f"no stow package '{package}' at {pkg_dir}")
        return
    home = Path.home()
    backup = home / ".dotfiles-backup" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    for f in pkg_dir.rglob("*"):
        if not f.is_file():
            continue
        rel = f.relative_to(pkg_dir)
        tgt = home / rel
        if tgt.exists() and not tgt.is_symlink():
            (backup / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(tgt), str(backup / rel))
            warn(f"backed up existing {rel} -> {backup / rel}")
    if run(["stow", "--no-folding", "--restow",
            "--target", str(home), "--dir", str(stowdir), package]).returncode == 0:
        ok(f"stowed {package}")
    else:
        warn(f"stow {package} failed")


def ensure_hook(entry, label="dotfiles"):
    """Idempotent guarded `source <entry>` block in ~/.zshrc."""
    entry = str(entry)
    rc = Path(os.environ.get("ZDOTDIR", str(Path.home()))) / ".zshrc"
    rc.touch(exist_ok=True)
    if entry in rc.read_text():
        ok(f"shell hook already present in {rc}")
        return
    with rc.open("a") as f:
        f.write(f"\n# >>> {label} hook >>>\nsource {entry}\n# <<< {label} hook <<<\n")
    ok(f"added shell hook to {rc}")


def install_deps():
    """The full dependency sweep (no stow/hook). Reused by wrapper installers."""
    step(f"Platform: {OS}   package manager: {pkg_manager()}")
    core_tools()
    setup_fd()
    setup_clangd()
    setup_tree_sitter()
    setup_pyenv()
    setup_omz()
    setup_fzf_keybindings()
    setup_python_deps()
    setup_claude()
    setup_font()


_NEXT_STEPS = """
Next steps:
  * Make zsh your login shell if it isn't:   chsh -s "$(command -v zsh)"
  * Open a new terminal (or `source ~/.zshrc`) so the config, aliases and PATH load.
  * Neovim installs its plugins on first launch (lazy.nvim); open `nvim` once
    and let it finish, then run :checkhealth to verify treesitter/LSP tooling.
"""


def main():
    install_deps()
    step("Deploying config via stow")
    deploy_pkg(DOTFILES_DIR, "config")
    if os.environ.get("DOTFILES_SKIP_SHELL"):
        warn("DOTFILES_SKIP_SHELL set; leaving ~/.zshrc hook to the wrapper installer")
    else:
        step("Wiring up the shell hook")
        ensure_hook(DOTFILES_DIR / "setup.zsh")
    step("Done.")
    print(_NEXT_STEPS)


if __name__ == "__main__":
    main()
