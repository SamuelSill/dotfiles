#!/usr/bin/env python3
"""Open a workspace — a pane layout plus the command that prepares it — in a zellij tab.

Workspaces are declared in the JSON files listed in $ZELLIJ_WORKSPACES_CONFIG
(colon-separated), each a list of {name, layout, setup} entries. `layout` names a
zellij layout file holding just the pane arrangement, and `setup` runs in every pane
before its own command — typically to cd somewhere — so one layout serves many
workspaces.

The layout is not handed to zellij as-is: `zellij action new-tab --layout` ignores
the session's default_tab_template, which would drop the status bar, so the panes
are spliced into that template (and into a `tab` node, to name the tab) first.
"""
import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

import layout_kdl as kdl
import layout_preview
from layout_kdl import (attribute, build_node, escape_string, find_node, indent,
                        node_body, node_header, node_name, split_nodes, string_values)

WORKSPACES_CONFIG_VAR = "ZELLIJ_WORKSPACES_CONFIG"
# Pane programs are handed to an interactive shell rather than executed directly, so
# that aliases resolve and a workspace's setup command can run first.
SHELL = "zsh"
SHELL_FLAGS = "-ic"
PANE_NODES = ("pane", "floating_panes")
TEMPLATE_NODES = ("pane_template", "tab_template")
# Nodes a workspace layout may declare that KDL only accepts at layout level, so
# they are lifted out of the generated `tab` node instead of being spliced into it.
LAYOUT_LEVEL_NODES = TEMPLATE_NODES + ("swap_tiled_layout", "swap_floating_layout")
MINIMUM_PREVIEW_LINES = 8
HEADING = "\033[1;38;2;137;180;250m"
SUBDUED = "\033[38;2;108;112;134m"
RESET = "\033[0m"


def die(message):
    print(f"launch-workspace: {message}", file=sys.stderr)
    # The picker usually runs in a pane that closes the moment this exits, so hold
    # the error on screen long enough to read it.
    if sys.stdin.isatty():
        input("\npress enter to close ")
    sys.exit(1)


def layout_nodes(path):
    try:
        return kdl.layout_nodes(path)
    except kdl.LayoutError as error:
        die(error)


def partition_nodes(nodes, names):
    """Split nodes by name into (matching, rest)."""
    matching = [node for node in nodes if node_name(node) in names]
    rest = [node for node in nodes if node_name(node) not in names]

    return matching, rest


def wrap_panes(nodes, setup):
    return [wrap_pane(node, setup) if node_name(node) in PANE_NODES else node
            for node in nodes]


def wrap_pane(node, setup):
    """Rewrite a pane to run its program through an interactive shell after `setup`.

    A pane's `command` and `args` become one shell command line, so aliases and shell
    syntax work in layouts, and the workspace's setup command runs ahead of it.
    `command` is taken as shell source; `args` are literal words, so they are quoted.
    The shell is left running afterwards unless the pane opted into `close_on_exit`.
    """
    children = split_nodes(node_body(node) or "")
    names = {node_name(child) for child in children}
    if "plugin" in names:
        return node

    header = node_header(node)
    if names & {"pane", "children"}:
        return build_node(header, wrap_panes(children, setup))

    program = []
    command = attribute(header, "command")
    if command:
        start, end, value = command
        header = header[:start] + header[end:]
        program.append(value)

    arguments = find_node(children, "args")
    if arguments:
        program += [shlex.quote(value) for value in string_values(arguments)]

    if not program and not setup:
        return node

    close_on_exit = attribute(header, "close_on_exit")
    keep_shell = close_on_exit is None or close_on_exit[2].lstrip("#") == "false"
    # `&&`: a setup that fails (a cd into a directory that isn't there) must not
    # leave the pane running its program somewhere unintended.
    steps = " && ".join(filter(None, [setup, " ".join(program)]))
    script = "; ".join(filter(None, [steps, f"exec {SHELL}" if keep_shell else ""]))
    body = [child for child in children if node_name(child) != "args"]

    return build_node(f'{header} command="{SHELL}"',
                      body + [f'args "{SHELL_FLAGS}" "{escape_string(script)}"'])


def tab_body(default_layout, pane_nodes):
    """The workspace's panes wrapped in the default tab template, if there is one.

    The template's `children` node marks where a tab's panes go, which is exactly
    where the workspace's panes belong — splicing them in is what keeps the bars
    the template declares. Its templates come along since it refers to them.
    """
    panes = "\n".join(indent(node, 0) for node in pane_nodes)
    if default_layout is None:
        return panes, []

    # Swap layouts are deliberately left behind: zellij re-applies them whenever a
    # tab's pane count changes, which would undo the workspace's own arrangement.
    templates, rest = partition_nodes(layout_nodes(default_layout), TEMPLATE_NODES)
    template = find_node(rest, "default_tab_template")
    if template is None:
        return panes, []

    body = [panes if node_name(node) == "children" else indent(node, 0)
            for node in split_nodes(node_body(template) or "")]

    return "\n".join(body), templates


def compose_layout(workspace, default_layout):
    hoisted, body_nodes = partition_nodes(layout_nodes(workspace["layout"]),
                                          LAYOUT_LEVEL_NODES)
    if not any(node_name(node) for node in body_nodes):
        die(f"{workspace['layout']} declares no panes")

    body, default_templates = tab_body(default_layout,
                                       wrap_panes(body_nodes, workspace["setup"]))
    name = escape_string(workspace["tab"])

    return "\n".join([
        "layout {",
        *(indent(node, 4) for node in default_templates + hoisted),
        f'    tab name="{name}" focus=true {{',
        indent(body, 8),
        "    }",
        "}",
        "",
    ])


# ── workspaces ─────────────────────────────────────────────────────────────────

def config_paths():
    configs = os.environ.get(WORKSPACES_CONFIG_VAR, "")
    paths = [Path(os.path.expanduser(entry)) for entry in configs.split(":") if entry]
    if not paths:
        die(f"${WORKSPACES_CONFIG_VAR} is not set")

    return paths


def expand(value, config):
    """Expand a configured path. Paths may lean on variables the shell exports, so an
    unset one is a mistake worth naming rather than a stray '$'."""
    expanded = os.path.expandvars(value)
    if "$" in expanded:
        die(f"{config}: {value} refers to a variable that is not set")

    return Path(expanded).expanduser()


def load_workspaces():
    """Workspaces from every configured file, later files overriding same-named ones."""
    workspaces = {}
    for path in config_paths():
        if not path.is_file():
            continue

        try:
            entries = json.loads(path.read_text())
        except (OSError, ValueError) as error:
            die(f"cannot read {path}: {error}")

        for entry in entries:
            try:
                name = entry["name"]
                layout = expand(entry["layout"], path)
            except KeyError as error:
                die(f"{path}: entry {entry} is missing {error}")

            workspaces[name] = {
                "name": name,
                "layout": layout if layout.is_absolute() else path.parent / layout,
                "tab": entry.get("tab", name),
                "setup": entry.get("setup", ""),
            }

    if not workspaces:
        die(f"no workspaces declared in {', '.join(str(p) for p in config_paths())}")

    return list(workspaces.values())


def default_layout_path():
    config_dir = Path(os.environ.get("ZELLIJ_CONFIG_DIR",
                                     Path.home() / ".config" / "zellij"))
    layout = config_dir / "layouts" / "default.kdl"

    return layout if layout.is_file() else None


# ── picker ─────────────────────────────────────────────────────────────────────

def preview(workspace):
    """What fzf shows beside the list: the layout drawn as the panes it opens."""
    print(f"{HEADING}{workspace['layout']}{RESET}")
    if workspace["setup"]:
        print(f"{SUBDUED}setup: {workspace['setup']}{RESET}\n")

    width = int(os.environ.get("FZF_PREVIEW_COLUMNS") or 80)
    height = int(os.environ.get("FZF_PREVIEW_LINES") or 24)
    try:
        nodes = partition_nodes(kdl.layout_nodes(workspace["layout"]),
                                LAYOUT_LEVEL_NODES)[1]
    except kdl.LayoutError as error:
        print(f"{SUBDUED}{error}{RESET}")

        return

    print(layout_preview.diagram(nodes, width, max(MINIMUM_PREVIEW_LINES, height - 4)))


def pick(workspaces):
    command = [
        "fzf",
        "--prompt=workspace> ",
        "--height=100%",
        "--preview", f"{shlex.quote(sys.executable)} "
                     f"{shlex.quote(str(Path(__file__).resolve()))} --preview {{}}",
        "--preview-window=right:65%",
    ]

    try:
        selection = subprocess.run(
            command, input="\n".join(workspace["name"] for workspace in workspaces),
            capture_output=True, text=True)
    except FileNotFoundError:
        die("fzf is not installed")

    if selection.returncode != 0 or not selection.stdout.strip():
        sys.exit(0)

    name = selection.stdout.strip()

    return next(workspace for workspace in workspaces if workspace["name"] == name)


def tab_exists(name):
    dump = subprocess.run(["zellij", "action", "dump-layout"],
                          capture_output=True, text=True)

    return f'tab name="{name}"' in dump.stdout


def open_workspace(workspace):
    if tab_exists(workspace["tab"]):
        subprocess.run(["zellij", "action", "go-to-tab-name", workspace["tab"]],
                       check=False)

        return

    layout = compose_layout(workspace, default_layout_path())
    with tempfile.NamedTemporaryFile("w", suffix=".kdl", prefix="zellij-workspace-",
                                     delete=False) as composed:
        composed.write(layout)

    result = subprocess.run(
        ["zellij", "action", "new-tab", "--layout", composed.name],
        capture_output=True, text=True)
    os.unlink(composed.name)

    if result.returncode != 0:
        die(f"zellij rejected the layout:\n{result.stderr or result.stdout}\n{layout}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", nargs="?",
                        help="workspace name; omit to pick one interactively")
    parser.add_argument("--print-layout", action="store_true",
                        help="print the composed layout instead of opening a tab")
    parser.add_argument("--preview", action="store_true",
                        help="draw the workspace's layout (used by the picker)")
    arguments = parser.parse_args()

    workspaces = load_workspaces()
    if arguments.workspace:
        selected = next((workspace for workspace in workspaces
                         if workspace["name"] == arguments.workspace), None)
        if selected is None:
            die(f"unknown workspace: {arguments.workspace}")
    else:
        selected = pick(workspaces)

    if arguments.preview:
        preview(selected)

        return

    if arguments.print_layout:
        print(compose_layout(selected, default_layout_path()), end="")

        return

    if not os.environ.get("ZELLIJ"):
        die("not inside a zellij session")

    open_workspace(selected)


if __name__ == "__main__":
    main()
