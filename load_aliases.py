#!/usr/bin/env python3
"""
Utility to load aliases from aliases.json and output shell-specific alias commands.
"""
import argparse
import json
import sys
import platform
from pathlib import Path

PLATFORM_KEY = {
    'Darwin': 'mac',
    'Linux': 'linux',
}


def resolve_command(command):
    """Resolve a command that may be a string or a dict mapping OS to command."""
    if isinstance(command, str):
        return command
    current_os = PLATFORM_KEY.get(platform.system())
    if current_os and current_os in command:
        return command[current_os]
    if 'default' in command:
        return command['default']
    raise ValueError(f"No command for platform '{platform.system()}' and no 'default' provided")


def create_alias_command(name, command, shell_type):
    """Create an alias/function command for the specified shell type."""
    import re
    if shell_type == 'sh':
        cmd_escaped = command.replace("'", "'\\''")

        # Check if command starts with its own name (e.g., claude -> claude --settings)
        # Use alias in this case since aliases have built-in recursion protection
        cmd_first_word = re.split(r'\s', command.strip())[0]
        if cmd_first_word == name:
            return f"alias {name}='{cmd_escaped}'"

        # Use functions for better syntax highlighting
        # If command doesn't already handle args ($@, $1, etc), append "$@"
        if not re.search(r'\$[@\d]', command):
            cmd_escaped = f'{cmd_escaped} "$@"'
        return f"{name}() {{ {cmd_escaped}; }}"
    else:
        raise ValueError(f"Unknown shell type: {shell_type}")


def generate_aliases(aliases, shell_type):
    """Generate alias commands for the specified shell type."""
    commands = []
    for alias_def in aliases:
        names = alias_def['name']
        cmd = resolve_command(alias_def['command'])
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
        choices=['sh'],
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
