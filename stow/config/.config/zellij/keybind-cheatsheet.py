#!/usr/bin/env python3

import json
import os
import sys
import shutil

RESET = "\x1b[0m"

# ── Built-in defaults ────────────────────────────────────────────────────────
# The JSON overrides these. `highlights` and `band` merge key-by-key; everything
# else (title, footer, sections) replaces. A text role is foreground + bold; the
# background comes from the section badge `color` or the `band` shades — so the
# roles layer cleanly over whatever background a row uses.
DEFAULTS = {
    "title": "zellij keybindings",
    "footer": "press any key to close",

    "highlights": {
        "title":  {"fg": "#b4befe", "bold": True},   # header
        "footer": {"fg": "#a6adc8"},                 # header hint (dim)
        "badge":  {"fg": "#11111b", "bold": True},   # section label, on `color`
        "key":    {"fg": "#a6e3a1", "bold": True},   # the keys
        "desc":   {"fg": "#cdd6f4"},                 # what they do
        "note":   {"fg": "#a6adc8"},                 # per-section footnote (dim)
    },

    # Item-chip background, with an alternating shade so adjacent chips separate
    # (like the old zellij hint bar). `bg_alt` defaults to `bg`. A section may
    # override this with its own `band`.
    "band": {"bg": "#2b3a55", "bg_alt": "#3a4d73"},

    # Fallback badge colour for a section that omits `color`.
    "section_color": "#585b70",

    "sections": [],
}


# ── ANSI helpers ─────────────────────────────────────────────────────────────
def _rgb(hex_color):
    h = hex_color.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def sgr(fg=None, bg=None, bold=False):
    """Build a truecolor SGR escape. bold is always emitted (1/22) so it never
    bleeds from a previous span within the same line."""
    codes = ["1" if bold else "22"]
    if fg:
        codes.append("38;2;{};{};{}".format(*_rgb(fg)))
    if bg:
        codes.append("48;2;{};{};{}".format(*_rgb(bg)))
    return "\x1b[" + ";".join(codes) + "m"


def style(spec, bg=None):
    """Turn a highlight spec ({fg, bg, bold}) into an SGR prefix, with an
    optional background override (used to drop a role onto a badge/band)."""
    return sgr(fg=spec.get("fg"), bg=bg if bg is not None else spec.get("bg"),
               bold=bool(spec.get("bold", False)))


# ── Config loading ───────────────────────────────────────────────────────────
def _deep_merge(base, override):
    for k, v in override.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            _deep_merge(base[k], v)
        else:
            base[k] = v
    return base


def config_path():
    env = os.environ.get("ZELLIJ_CHEATSHEET_CONFIG")
    if env:
        return env
    if len(sys.argv) > 1 and sys.argv[1]:
        return sys.argv[1]
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "cheatsheet.json")


def load_config():
    cfg = json.loads(json.dumps(DEFAULTS))  # deep copy of defaults
    path = config_path()
    try:
        with open(path, "r", encoding="utf-8") as f:
            user = json.load(f)
        # Drop `_comment`-style annotation keys before merging.
        user = {k: v for k, v in user.items() if not k.startswith("_")}
        _deep_merge(cfg, user)
    except FileNotFoundError:
        cfg["_error"] = "config not found: {}".format(path)
    except (json.JSONDecodeError, OSError) as e:
        cfg["_error"] = "config error in {}: {}".format(path, e)
    return cfg


# ── Rendering ────────────────────────────────────────────────────────────────
def render(cfg):
    cols = max(24, shutil.get_terminal_size((100, 40)).columns)
    hi = cfg["highlights"]
    indent = "  "
    out = []

    # Header: title (bright) + footer hint (dim).
    header = ""
    if cfg.get("title"):
        header += style(hi["title"]) + " " + cfg["title"] + " " + RESET
    if cfg.get("footer"):
        header += "   " + style(hi["footer"]) + cfg["footer"] + RESET
    if header:
        out.append(header)

    if cfg.get("_error"):
        out.append("")
        out.append(style(hi["note"]) + indent + cfg["_error"] + RESET)
        return "\n".join(out) + "\n"

    default_band = cfg["band"]
    for sec in cfg.get("sections", []):
        out.append("")  # gap between sections
        color = sec.get("color", cfg.get("section_color", "#585b70"))
        out.append(style(hi["badge"], bg=color) + " " + sec.get("title", "") + " " + RESET)

        band = dict(default_band)
        band.update(sec.get("band", {}))
        bg, bg_alt = band.get("bg"), band.get("bg_alt", band.get("bg"))

        cur, curw = indent, len(indent)
        for i, item in enumerate(sec.get("items", [])):
            key = str(item[0]) if item else ""
            desc = str(item[1]) if len(item) > 1 else ""
            chip_bg = bg if i % 2 == 0 else bg_alt
            width = len(key) + len(desc) + 3  # " key desc "
            if curw > len(indent) and curw + width > cols:
                out.append(cur)
                cur, curw = indent, len(indent)
            cur += (style(hi["key"], bg=chip_bg) + " " + key + " "
                    + style(hi["desc"], bg=chip_bg) + desc + " " + RESET)
            curw += width
        if curw > len(indent):
            out.append(cur)

        if sec.get("note"):
            out.append(indent + style(hi["note"]) + sec["note"] + RESET)

    return "\n".join(out) + "\n"


# ── Wait for a keypress, then exit (pane closes via close_on_exit) ───────────
def wait_for_key():
    import termios
    import tty
    try:
        fd = os.open("/dev/tty", os.O_RDONLY)
    except OSError:
        fd = sys.stdin.fileno()
    old = None
    try:
        old = termios.tcgetattr(fd)
        tty.setraw(fd)
        os.read(fd, 1)
    except Exception:
        try:
            sys.stdin.readline()
        except Exception:
            pass
    finally:
        if old is not None:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
            except Exception:
                pass


def main():
    cfg = load_config()
    sys.stdout.write("\x1b[2J\x1b[H")  # clear + home
    sys.stdout.write(render(cfg))
    sys.stdout.flush()
    wait_for_key()


if __name__ == "__main__":
    main()
