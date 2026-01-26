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
    """Create an alias command for the specified shell type."""
    if shell_type == 'sh':
        # Escape single quotes in the command
        cmd_escaped = command.replace("'", "'\\''")
        return f"alias {name}='{cmd_escaped}'"
    elif shell_type == 'powershell':
        # Create a function that invokes the command
        cmd_escaped = command.replace('"', '`"')
        return f"function global:{name} {{ Invoke-Expression '{cmd_escaped}' }}"
    else:
        raise ValueError(f"Unknown shell type: {shell_type}")


def generate_aliases(aliases, script_dir, shell_type):
    """Generate alias commands for the specified shell type."""
    # Determine the variable name for script directory based on shell
    script_var = '$SCRIPT_DIR' if shell_type == 'sh' else '$ScriptDir'

    commands = []
    for alias_def in aliases:
        name = alias_def['name']
        cmd = alias_def['command']
        # Expand $SCRIPT_DIR in the command
        cmd = cmd.replace('$SCRIPT_DIR', script_dir if shell_type == 'sh' else script_var)
        commands.append(create_alias_command(name, cmd, shell_type))

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
        'script_dir',
        help='Directory containing the aliases.json file'
    )

    args = parser.parse_args()

    # Find aliases.json in the same directory as this script
    this_dir = Path(__file__).parent
    aliases_path = this_dir / 'aliases.json'

    if not aliases_path.exists():
        print(f"Error: {aliases_path} not found", file=sys.stderr)
        return 1

    try:
        with open(aliases_path, 'r') as f:
            aliases = json.load(f)

        if args.shell_type not in ('sh', 'powershell'):
            print(f"Error: Unknown shell type '{args.shell_type}'", file=sys.stderr)
            return 1

        output = generate_aliases(aliases, args.script_dir, args.shell_type)
        print(output)
        return 0

    except Exception as e:
        print(f"Error loading aliases: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
