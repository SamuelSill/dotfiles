#!/usr/bin/env python3
"""
Utility to load aliases from aliases.json and output shell-specific alias commands.
"""
import argparse
import json
import sys
import os
from pathlib import Path


def create_alias_command(name, command, shell_type):
    """Create an alias/function command for the specified shell type."""
    if shell_type == 'sh':
        # Use functions instead of aliases for better syntax highlighting
        # Functions are validated by name only, not by content
        cmd_escaped = command.replace("'", "'\\''")
        return f"{name}() {{ {cmd_escaped}; }}"
    elif shell_type == 'powershell':
        # Create a function that invokes the command
        cmd_escaped = command.replace('"', '`"')
        return f"function global:{name} {{ Invoke-Expression '{cmd_escaped}' }}"
    else:
        raise ValueError(f"Unknown shell type: {shell_type}")


def generate_aliases(aliases, shell_type):
    """Generate alias commands for the specified shell type."""
    commands = []
    for alias_def in aliases:
        names = alias_def['name']
        cmd = alias_def['command']
        # Support both string and array for "name"
        if isinstance(names, str):
            names = [names]
        for name in names:
            commands.append(create_alias_command(name, cmd, shell_type))
            print(commands[-1])

    return '\n'.join(commands)


def main():
    parser = argparse.ArgumentParser(
        description='Load aliases from aliases.json and output shell-specific alias commands'
    )
    parser.add_argument(
        'shell_type',
        choices=['sh', 'powershell'],
        help='Shell type to generate aliases for'
    )

    parser.add_argument(
        "alias_file",
        help="Path to the aliases JSON file"
    )

    args = parser.parse_args()
    aliases_path = Path(args.alias_file)

    if not aliases_path.exists():
        print(f"Error: {aliases_path} not found", file=sys.stderr)
        return 1

    try:
        with open(aliases_path, 'r') as f:
            aliases = json.load(f)

        output = generate_aliases(aliases, args.shell_type)
        print(output)
        return 0

    except Exception as e:
        print(f"Error loading aliases: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
