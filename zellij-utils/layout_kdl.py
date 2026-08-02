"""A reader for the slice of KDL that zellij layouts use.

Nodes are picked apart and put back together verbatim, so layouts keep every zellij
feature — stacks, splits, sizes, plugins, floating panes — and every comment, without
this module knowing about any of them. That round trip, not parsing, is why there is
no KDL library here: the composed layout carries over a chunk of the user's own
default layout, which a parse-and-reserialise would strip of its comments.

Only what zellij's layouts (KDL v1) actually contain is understood. Hashed raw
strings, \\u escapes and type annotations are not; slashdash-commented nodes are
passed through untouched, which leaves zellij to ignore them.
"""
from pathlib import Path

STRING_ESCAPES = {"n": "\n", "t": "\t", "r": "\r"}


class LayoutError(Exception):
    """A layout file that cannot be read as a zellij layout."""


def code_mask(source):
    """Mark every character of `source` that is neither in a string nor a comment.

    Braces, newlines and semicolons only delimit nodes where this mask is set.
    """
    mask = [False] * len(source)
    index = 0
    while index < len(source):
        if source[index] == '"':
            index += 1
            while index < len(source) and source[index] != '"':
                index += 2 if source[index] == "\\" else 1
            index += 1
        elif source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end == -1 else end
        elif source.startswith("/*", index):
            end = source.find("*/", index)
            index = len(source) if end == -1 else end + 2
        else:
            mask[index] = True
            index += 1

    return mask


def split_nodes(source):
    """Split KDL source into its top-level nodes, each returned verbatim."""
    mask = code_mask(source)
    nodes = []
    depth = 0
    start = 0
    for index, char in enumerate(source):
        if not mask[index]:
            continue

        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif char in ";\n" and depth == 0:
            node = source[start:index].strip()
            if node:
                nodes.append(node)
            start = index + 1

    node = source[start:].strip()
    if node:
        nodes.append(node)

    return nodes


def node_name(node):
    """A node's name, skipping any comment lines that precede it."""
    mask = code_mask(node)
    name = []
    for index, char in enumerate(node):
        if not mask[index] or char.isspace() or char in "{;":
            if name:
                break
            continue

        name.append(char)

    return "".join(name)


def node_body(node):
    """The source inside a node's braces, or None for a childless node."""
    mask = code_mask(node)
    depth = 0
    start = None
    for index, char in enumerate(node):
        if not mask[index]:
            continue

        if char == "{":
            depth += 1
            if depth == 1:
                start = index + 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return node[start:index]

    return None


def find_node(nodes, name):
    return next((node for node in nodes if node_name(node) == name), None)


def read_string(source, index):
    """Read the string literal at source[index], returning (value, index after it)."""
    value = []
    index += 1
    while index < len(source) and source[index] != '"':
        if source[index] == "\\" and index + 1 < len(source):
            value.append(STRING_ESCAPES.get(source[index + 1], source[index + 1]))
            index += 2
        else:
            value.append(source[index])
            index += 1

    return "".join(value), index + 1


def string_values(source):
    """Every string literal in a node, in order — a node's arguments."""
    values = []
    index = 0
    while index < len(source):
        if source[index] == '"':
            value, index = read_string(source, index)
            values.append(value)
        elif source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end == -1 else end
        elif source.startswith("/*", index):
            end = source.find("*/", index)
            index = len(source) if end == -1 else end + 2
        else:
            index += 1

    return values


def escape_string(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def attribute(header, name):
    """Locate `name=<value>` in a node's header, as (start, end, value).

    Values are either quoted strings (`command="nvim"`) or bare words (`focus=true`).
    """
    mask = code_mask(header)
    token = f"{name}="
    index = header.find(token)
    while index != -1:
        assigned = index + len(token)
        if all(mask[index:assigned]) and (index == 0 or header[index - 1].isspace()):
            if header[assigned:assigned + 1] == '"':
                value, end = read_string(header, assigned)
            else:
                end = assigned
                while end < len(header) and not header[end].isspace():
                    end += 1
                value = header[assigned:end]

            # Swallow the preceding whitespace too, so removal leaves no double space.
            while index > 0 and header[index - 1] in " \t":
                index -= 1

            return index, end, value

        index = header.find(token, index + 1)

    return None


def indent(source, level):
    """Re-indent a node to `level`, keeping the relative indentation of its body.

    Nodes come out of split_nodes with their first line stripped but the rest still
    carrying the indentation of the file they came from.
    """
    lines = source.strip("\n").splitlines()
    body = [line for line in lines[1:] if line.strip()]
    common = min((len(line) - len(line.lstrip()) for line in body), default=0)
    prefix = " " * level

    return "\n".join([prefix + lines[0]]
                     + [prefix + line[common:] if line.strip() else line
                        for line in lines[1:]])


def node_header(node):
    """A node's source up to its body — its name and arguments."""
    mask = code_mask(node)
    for index, char in enumerate(node):
        if mask[index] and char == "{":
            return node[:index].rstrip()

    return node.rstrip()


def build_node(header, children):
    if not children:
        return header

    return "\n".join([header + " {", *(indent(child, 4) for child in children), "}"])


def layout_nodes(path):
    """The top-level nodes inside a layout file's `layout` node."""
    try:
        source = Path(path).read_text()
    except OSError as error:
        raise LayoutError(f"cannot read layout {path}: {error}") from error

    layout = find_node(split_nodes(source), "layout")
    if layout is None:
        raise LayoutError(f"{path} has no top-level `layout` node")

    return split_nodes(node_body(layout) or "")
