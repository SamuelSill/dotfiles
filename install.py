#!/usr/bin/env python3
import datetime
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
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


def setup_bat():
    """Debian names the binary 'batcat'; our aliases call 'bat'. Ensure a 'bat' on PATH.
    bat syntax-highlights piped output (e.g. the dlp-agent remote build's Rust errors)."""
    if have("bat"):
        ok("bat")
        return
    step("Installing bat")
    pm_install({"brew": "bat", "apt": "bat", "dnf": "bat", "pacman": "bat"}[pkg_manager()])
    if have("bat"):
        ok("bat")
        return
    if have("batcat"):
        src = shutil.which("batcat")
        if os.access("/usr/local/bin", os.W_OK) or sudo_prefix():
            run(sudo_prefix() + ["ln", "-sf", src, "/usr/local/bin/bat"])
            ok("linked batcat -> /usr/local/bin/bat")
        else:
            (Path.home() / ".local/bin").mkdir(parents=True, exist_ok=True)
            run(["ln", "-sf", src, str(Path.home() / ".local/bin/bat")])
            warn("linked batcat -> ~/.local/bin/bat (ensure ~/.local/bin is on PATH)")


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
    setup_bat()
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


_MEDIA_KEYS = "org.gnome.settings-daemon.plugins.media-keys"
_KEYBIND_BASE = f"/{_MEDIA_KEYS.replace('.', '/')}/custom-keybindings"

_FAVORITE_APPS = ["kitty.desktop", "slack.desktop", "google-chrome.desktop"]

_EXTENSIONS_SITE = "https://extensions.gnome.org"
_FOCUS_CHANGER_UUID = "focus-changer@heartmire"
_DIRECTIONAL_FOCUS_BINDINGS = {"focus-left": "h", "focus-down": "j",
                               "focus-up": "k", "focus-right": "l"}

# Super+h minimizes and Super+l locks the screen by default; a shell extension's
# binding loses to both, so the focus keys only fire once these move off those keys.
# Minimize shifts onto Super+Shift+h; lock can't just move here (see
# setup_lock_screen_shortcut) so it is cleared and re-added as a custom shortcut.
_DIRECTIONAL_FOCUS_REBINDS = [
    ("org.gnome.desktop.wm.keybindings", "minimize", ["<Super><Shift>h"]),
    ("org.gnome.settings-daemon.plugins.media-keys", "screensaver", []),
]

_LOCK_SCREEN_BINDING = "<Super><Shift>l"
_LOCK_SCREEN_COMMAND = ("gdbus call -e -d org.gnome.ScreenSaver "
                        "-o /org/gnome/ScreenSaver -m org.gnome.ScreenSaver.Lock")


def setup_per_window_input_source():
    """Make the keyboard layout a per-window property instead of a global one.

    GNOME implements this but exposes no UI for it; the shell watches the key, so
    the change takes effect without a re-login.
    """
    if not have("gsettings"):
        return  # not a GNOME desktop

    run(["gsettings", "set", "org.gnome.desktop.input-sources", "per-window", "true"])
    ok("keyboard layout is now remembered per window")


def setup_app_favorites(extra_favorites=()):
    """Pin the dash favorites that GNOME's Super+1..9 shortcuts activate, in order.

    switch-to-application-N focuses favorite N's window when the app is running and
    launches it otherwise. GNOME drops a favorite whose desktop entry is missing or
    hidden, which silently shifts every number after it — so unusable entries are
    filtered out loudly rather than left to renumber the rest. We also assert the
    bindings themselves, since switch-to-workspace-N on the same keys wins the
    conflict and leaves the shortcut dead.
    """
    if not have("gsettings"):
        return  # not a GNOME desktop

    wanted = [*_FAVORITE_APPS, *extra_favorites]
    favorites = [app for app in wanted if _is_listed_desktop_entry(app)]
    for app in wanted:
        if app not in favorites:
            warn(f"{app} is not installed or is hidden; skipping it "
                 "(the remaining Super+N numbers shift up by one)")
    run(["gsettings", "set", "org.gnome.shell", "favorite-apps",
         "[" + ", ".join(f"'{app}'" for app in favorites) + "]"])
    for i, app in enumerate(favorites[:9], start=1):
        run(["gsettings", "set", "org.gnome.shell.keybindings",
             f"switch-to-application-{i}", f"['<Super>{i}']"])
        run(["gsettings", "set", "org.gnome.desktop.wm.keybindings",
             f"switch-to-workspace-{i}", "[]"])
        ok(f"Super+{i} -> {app}")


def setup_directional_window_focus():
    """Bind Super+h/j/k/l to move focus to the window in that direction.

    Mutter has no directional-focus concept and Wayland forbids anything outside the
    compositor from moving focus, so this needs a shell extension (focus-changer).
    """
    if not have("gsettings") or not have("gnome-extensions"):
        return  # not a GNOME desktop

    extension = Path.home() / ".local/share/gnome-shell/extensions" / _FOCUS_CHANGER_UUID
    if not extension.is_dir() and not _install_shell_extension(_FOCUS_CHANGER_UUID):
        return

    _enable_shell_extension(_FOCUS_CHANGER_UUID)
    for schema, key, bindings in _DIRECTIONAL_FOCUS_REBINDS:
        run(["gsettings", "set", schema, key,
             "[" + ", ".join(f"'{binding}'" for binding in bindings) + "]"])

    # The extension's schema isn't in the system schema path, so gsettings needs
    # pointing at the copy it ships.
    env = {**os.environ, "GSETTINGS_SCHEMA_DIR": str(extension / "schemas")}
    for key, letter in _DIRECTIONAL_FOCUS_BINDINGS.items():
        run(["gsettings", "set", "org.gnome.shell.extensions.focus-changer",
             key, f"['<Super>{letter}']"], env=env)
    ok("Super+h/j/k/l focus the window left/down/up/right")


def setup_lock_screen_shortcut():
    """Re-home the lock screen on Super+Shift+l, since directional focus takes Super+l.

    A custom shortcut rather than just moving the built-in `screensaver` binding:
    gsd-media-keys doesn't re-grab that accelerator when the setting changes, so
    moving it leaves the machine with no working lock key until the next login.
    """
    if not have("gsettings"):
        return  # not a GNOME desktop

    _register_gnome_keybind("lock-screen", "Lock screen",
                            _LOCK_SCREEN_COMMAND, _LOCK_SCREEN_BINDING)


def _install_shell_extension(uuid):
    """Fetch <uuid> from extensions.gnome.org for the running shell and install it."""
    shell_version = _out(["gnome-shell", "--version"]).split()[-1].split(".")[0]
    query = urllib.parse.urlencode({"uuid": uuid, "shell_version": shell_version})
    try:
        with urllib.request.urlopen(f"{_EXTENSIONS_SITE}/extension-info/?{query}",
                                    timeout=30) as response:
            download_path = json.load(response)["download_url"]
        with urllib.request.urlopen(_EXTENSIONS_SITE + download_path, timeout=60) as response:
            archive_bytes = response.read()
    except Exception as error:
        warn(f"could not fetch {uuid} for GNOME Shell {shell_version}: {error}")

        return False

    tmp = tempfile.mkdtemp()
    archive = Path(tmp, "extension.zip")
    archive.write_bytes(archive_bytes)
    installed = run(["gnome-extensions", "install", "--force", str(archive)]).returncode == 0
    shutil.rmtree(tmp, ignore_errors=True)
    if installed:
        ok(f"installed {uuid}")
    else:
        warn(f"could not install {uuid}")

    return installed


def _enable_shell_extension(uuid):
    """Enable <uuid> by writing enabled-extensions directly.

    `gnome-extensions enable` asks the running shell, which only scans the extension
    directory at startup and so rejects a just-installed uuid; the gsettings key is
    read at next login regardless.
    """
    enabled = re.findall(r"'([^']*)'", _out(["gsettings", "get", "org.gnome.shell",
                                            "enabled-extensions"]))
    if uuid in enabled:
        ok(f"{uuid} already enabled")
        return

    enabled.append(uuid)
    run(["gsettings", "set", "org.gnome.shell", "enabled-extensions",
         "[" + ", ".join(f"'{e}'" for e in enabled) + "]"])
    ok(f"enabled {uuid} (active after the next login)")


def _desktop_entry_dirs():
    data_home = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")

    return [Path(d, "applications") for d in [data_home, *data_dirs.split(":")]]


def _is_listed_desktop_entry(desktop_id):
    """True if <desktop_id> exists and GNOME will list it as an app (some packages
    ship a NoDisplay duplicate of their entry, which can never be a favorite)."""
    for directory in _desktop_entry_dirs():
        entry = directory / desktop_id
        if not entry.is_file():
            continue
        main_group = entry.read_text(errors="replace").split("[Desktop Entry]", 1)[-1] \
                                                      .split("\n[", 1)[0]

        return not re.search(r"^(NoDisplay|Hidden)\s*=\s*true", main_group,
                             re.MULTILINE | re.IGNORECASE)

    return False


def _register_gnome_keybind(key, name, command, binding):
    """Idempotently add one GNOME media-keys custom shortcut, preserving any others."""
    path = f"{_KEYBIND_BASE}/{key}/"
    paths = re.findall(r"'([^']*)'", _out(["gsettings", "get", _MEDIA_KEYS,
                                           "custom-keybindings"]))
    if path not in paths:
        paths.append(path)
        run(["gsettings", "set", _MEDIA_KEYS, "custom-keybindings",
             "[" + ", ".join(f"'{p}'" for p in paths) + "]"])
    schema = f"{_MEDIA_KEYS}.custom-keybinding:{path}"
    run(["gsettings", "set", schema, "name", name])
    run(["gsettings", "set", schema, "command", command])
    run(["gsettings", "set", schema, "binding", binding])
    ok(f"GNOME shortcut '{name}' bound to {binding}")


def main():
    install_deps()
    step("Deploying config via stow")
    deploy_pkg(DOTFILES_DIR, "config")
    deploy_pkg(DOTFILES_DIR, "claude")
    step("Setting up per-window keyboard layout")
    setup_per_window_input_source()
    step("Pinning the Super+1..9 app favorites")
    setup_app_favorites()
    step("Setting up Super+h/j/k/l directional window focus")
    setup_directional_window_focus()
    step("Re-homing the lock screen on Super+Shift+L")
    setup_lock_screen_shortcut()
    if os.environ.get("DOTFILES_SKIP_SHELL"):
        warn("DOTFILES_SKIP_SHELL set; leaving ~/.zshrc hook to the wrapper installer")
    else:
        step("Wiring up the shell hook")
        ensure_hook(DOTFILES_DIR / "setup.zsh")
    step("Done.")
    print(_NEXT_STEPS)


if __name__ == "__main__":
    main()
