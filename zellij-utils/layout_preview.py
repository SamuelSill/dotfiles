#!/usr/bin/env python3
"""Draw a zellij layout as a diagram of the panes it opens.

Splits become nested boxes sized by their `size` attribute; a stack becomes one box
listing what it holds, which is how zellij shows it — one pane at a time.
"""
from collections import namedtuple

import layout_kdl as kdl

ESC = "\033"
BORDER = f"{ESC}[38;2;108;112;134m"     # overlay0
NAME = f"{ESC}[1;38;2;137;180;250m"     # bold blue
COMMAND = f"{ESC}[38;2;205;214;244m"    # text
STACK = f"{ESC}[38;2;249;226;175m"      # yellow
DIM = f"{ESC}[38;2;108;112;134m"        # overlay0
RESET = f"{ESC}[0m"

UP, DOWN, LEFT, RIGHT = 1, 2, 4, 8
BOX_CHARS = {
    UP: "│", DOWN: "│", UP | DOWN: "│",
    LEFT: "─", RIGHT: "─", LEFT | RIGHT: "─",
    DOWN | RIGHT: "┌", DOWN | LEFT: "┐", UP | RIGHT: "└", UP | LEFT: "┘",
    UP | DOWN | RIGHT: "├", UP | DOWN | LEFT: "┤",
    DOWN | LEFT | RIGHT: "┬", UP | LEFT | RIGHT: "┴",
    UP | DOWN | LEFT | RIGHT: "┼",
}
STACK_GLYPH = "▤"
MINIMUM_SPAN = 2
ELLIPSIS = "…"

Size = namedtuple("Size", "value percent")


class Pane:
    """A node of the layout's pane tree, as far as drawing it is concerned."""

    def __init__(self, name, command, size, columns, stacked, plugin, children):
        self.name = name
        self.command = command
        self.size = size
        self.columns = columns
        self.stacked = stacked
        self.plugin = plugin
        self.children = children

    @property
    def label(self):
        return self.name or ("plugin" if self.plugin else "shell")


def pane_command(header, children):
    """A pane's program as one displayable command line."""
    command = kdl.attribute(header, "command")
    words = [command[2]] if command else []
    arguments = kdl.find_node(children, "args")
    if arguments:
        words += kdl.string_values(arguments)

    return " ".join(words)


def parse_size(header):
    """A pane's `size`: a share of its parent, a number of cells, or None for both."""
    size = kdl.attribute(header, "size")
    if size is None:
        return None

    value = size[2].strip()
    try:
        if value.endswith("%"):
            return Size(float(value.rstrip("%")) / 100, percent=True)

        return Size(int(value), percent=False)
    except ValueError:
        return None


def flag(header, name):
    attribute = kdl.attribute(header, name)

    return attribute is not None and attribute[2].lstrip("#") != "false"


def parse_pane(node):
    children = kdl.split_nodes(kdl.node_body(node) or "")
    header = kdl.node_header(node)
    name = kdl.attribute(header, "name")
    direction = kdl.attribute(header, "split_direction")

    return Pane(
        name=name[2] if name else "",
        command=pane_command(header, children),
        size=parse_size(header),
        columns=direction is not None and direction[2].startswith("vertical"),
        stacked=flag(header, "stacked"),
        plugin=kdl.find_node(children, "plugin") is not None,
        children=[parse_pane(child) for child in children
                  if kdl.node_name(child) == "pane"],
    )


def parse_layout(nodes):
    """The panes of a layout body, plus its floating panes listed separately."""
    panes = [parse_pane(node) for node in nodes if kdl.node_name(node) == "pane"]
    floating = [parse_pane(node)
                for group in nodes if kdl.node_name(group) == "floating_panes"
                for node in kdl.split_nodes(kdl.node_body(group) or "")
                if kdl.node_name(node) == "pane"]

    return panes, floating


# ── drawing ────────────────────────────────────────────────────────────────────

class Canvas:
    """A character grid that merges box borders where panes meet."""

    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.cells = [[(" ", "")] * width for _ in range(height)]
        self.borders = {}

    def write(self, x, y, text, style):
        for offset, char in enumerate(text):
            if 0 <= y < self.height and 0 <= x + offset < self.width:
                self.cells[y][x + offset] = (char, style)

    def connect(self, x, y, mask):
        if 0 <= x < self.width and 0 <= y < self.height:
            self.borders[(x, y)] = self.borders.get((x, y), 0) | mask

    def box(self, left, top, right, bottom):
        for x in range(left, right + 1):
            self.connect(x, top, (LEFT if x > left else 0) | (RIGHT if x < right else 0))
            self.connect(x, bottom, (LEFT if x > left else 0) | (RIGHT if x < right else 0))

        for y in range(top, bottom + 1):
            self.connect(left, y, (UP if y > top else 0) | (DOWN if y < bottom else 0))
            self.connect(right, y, (UP if y > top else 0) | (DOWN if y < bottom else 0))

    def render(self):
        for (x, y), mask in self.borders.items():
            self.cells[y][x] = (BOX_CHARS.get(mask, "─"), BORDER)

        return "\n".join(self.render_row(row) for row in self.cells)

    @staticmethod
    def render_row(row):
        line = []
        style = ""
        for char, cell_style in row:
            if cell_style != style:
                line.append(RESET if not cell_style else cell_style)
                style = cell_style

            line.append(char)

        return "".join(line).rstrip() + RESET


def spans(total, sizes):
    """Cells per sibling: percentages of the whole, fixed sizes as given, and whatever
    is left shared equally by the panes that asked for no particular size."""
    cells = [None if size is None else
             max(MINIMUM_SPAN, round(size.value * total) if size.percent else size.value)
             for size in sizes]
    flexible = [index for index, cell in enumerate(cells) if cell is None]
    remaining = total - sum(cell for cell in cells if cell is not None)
    for index in flexible:
        cells[index] = max(MINIMUM_SPAN, remaining // len(flexible))

    return balance(cells, total)


def balance(cells, total):
    """Nudge the largest span so they add up to exactly the space available."""
    drift = total - sum(cells)
    if drift and cells:
        largest = cells.index(max(cells))
        cells[largest] = max(MINIMUM_SPAN, cells[largest] + drift)

    return cells


def cuts(start, end, panes):
    """Where to split `start`..`end` between sibling panes, sharing their borders."""
    positions = [start]
    for cells in spans(end - start, [pane.size for pane in panes])[:-1]:
        positions.append(min(positions[-1] + cells, end))

    positions.append(end)

    return positions


def draw(canvas, pane, left, top, right, bottom):
    children = pane.children
    if children and not pane.stacked:
        draw_split(canvas, pane, children, left, top, right, bottom)

        return

    canvas.box(left, top, right, bottom)
    if pane.stacked:
        draw_stack(canvas, children, left, top, right, bottom)

        return

    draw_label(canvas, pane.label, pane.command, left, top, right, bottom)


def draw_split(canvas, pane, children, left, top, right, bottom):
    if pane.columns:
        positions = cuts(left, right, children)
        for index, child in enumerate(children):
            draw(canvas, child, positions[index], top, positions[index + 1], bottom)

        return

    positions = cuts(top, bottom, children)
    for index, child in enumerate(children):
        draw(canvas, child, left, positions[index], right, positions[index + 1])


def fit(text, width):
    if width < 1:
        return ""

    return text if len(text) <= width else text[:width - 1] + ELLIPSIS


def draw_stack(canvas, children, left, top, right, bottom):
    """A stack shows one pane at a time, so list its panes instead of splitting."""
    width = right - left - 5
    for index, child in enumerate(children):
        if top + 1 + index >= bottom:
            break

        canvas.write(left + 2, top + 1 + index,
                     STACK_GLYPH if index == 0 else " ", STACK)
        label = fit(child.label, width)
        canvas.write(left + 4, top + 1 + index, label, NAME)
        room = width - len(label) - 2
        command = fit(child.command, room)
        if command:
            canvas.write(right - 1 - len(command), top + 1 + index, command, DIM)


def draw_label(canvas, name, command, left, top, right, bottom):
    width = right - left - 3
    if width < 1 or bottom - top < 2:
        return

    canvas.write(left + 2, top + 1, fit(name, width), NAME)
    if command and bottom - top > 3:
        canvas.write(left + 2, top + 3, fit(command, width), COMMAND)


def diagram(nodes, width, height):
    """The layout's panes drawn into a grid of the given size."""
    panes, floating = parse_layout(nodes)
    if not panes:
        return "(no panes)"

    canvas = Canvas(width, height)
    root = panes[0] if len(panes) == 1 else Pane("", "", None, False, False, False, panes)
    draw(canvas, root, 0, 0, width - 1, height - 1)
    lines = [canvas.render()]
    for pane in floating:
        lines.append(f"{DIM}  floating: {pane.label} "
                     f"{'· ' + pane.command if pane.command else ''}{RESET}")

    return "\n".join(lines)
