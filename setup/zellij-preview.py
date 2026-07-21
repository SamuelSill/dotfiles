#!/usr/bin/env python3
"""fzf preview for the zellij-a picker: one section per pane, headed by its cwd and
listing the programs running in it (the pane's own zsh shell is omitted)."""
import os
import sys

ESC = "\033"
PROG_BG = f"{ESC}[48;2;49;50;68m"       # surface0
CWD_BG = f"{ESC}[48;2;69;71;90m"        # surface1
PROG_FG = f"{ESC}[38;2;205;214;244m"    # text
NAME_FG = f"{ESC}[1;38;2;137;180;250m"  # bold blue
CWD_FG = f"{ESC}[3;38;2;148;226;213m"   # italic teal
DIM = f"{ESC}[38;2;108;112;134m"        # overlay0
RST = f"{ESC}[0m"

WIDTH = int(os.environ.get("FZF_PREVIEW_COLUMNS") or 80)
HOME = os.path.expanduser("~")


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def cmdline(pid):
    return " ".join(read(f"/proc/{pid}/cmdline").split("\0")).strip()


def cwd(pid):
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return ""


def children_map():
    kids = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        stat = read(f"/proc/{pid}/stat")
        try:  # comm (2nd field) may contain spaces, so scan past the closing ')'
            ppid = int(stat[stat.rfind(")") + 1:].split()[1])
        except (ValueError, IndexError):
            continue
        kids.setdefault(ppid, []).append(int(pid))
    for children in kids.values():
        children.sort()
    return kids


def find_server(session):
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        cmd = cmdline(pid)
        if "zellij --server" in cmd and cmd.endswith(f"/{session}"):
            return int(pid)
    return None


def abbreviate(path):
    if path == HOME:
        return "~"
    if path.startswith(HOME + "/"):
        return "~" + path[len(HOME):]
    return path


def cwd_line(path):
    text = " " + abbreviate(path)
    if len(text) > WIDTH:
        text = text[:WIDTH - 1] + "…"
    return f"{CWD_BG}{CWD_FG}{text}{' ' * (WIDTH - len(text))}{RST}"


def program_line(indent, args):
    avail = max(1, WIDTH - len(indent))
    binary, sep, rest = args.partition(" ")
    base, tail = binary.rsplit("/", 1)[-1], sep + rest
    visible = base + tail
    if len(visible) > avail:
        visible = visible[:avail - 1] + "…"
        base, tail = (visible, "") if len(base) >= len(visible) else (base, visible[len(base):])
    pad = " " * max(0, avail - len(visible))
    return f"{indent}{PROG_BG}{NAME_FG}{base}{RST}{PROG_BG}{PROG_FG}{tail}{pad}{RST}"


def emit(pid, indent, kids, out):
    args = cmdline(pid)
    if not args:
        return
    out.append(program_line(indent, args))
    for child in kids.get(pid, []):
        emit(child, indent + "  ", kids, out)


def main():
    session = sys.argv[1] if len(sys.argv) > 1 else ""
    srv = find_server(session)
    if srv is None:
        print(f"{DIM}no running programs{RST}")
        return
    kids = children_map()
    rule = "─" * WIDTH
    out = []
    for i, pane in enumerate(kids.get(srv, [])):
        if i:
            out.append(f"{DIM}{rule}{RST}")
        out.append(cwd_line(cwd(pane)))
        pane_kids = kids.get(pane, [])
        if pane_kids:
            for child in pane_kids:
                emit(child, "  ", kids, out)
        else:
            out.append(f"{DIM}  idle{RST}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
