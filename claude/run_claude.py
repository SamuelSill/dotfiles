#!/usr/bin/env python3
"""
Launch Claude Code with claude-settings.json, expanding environment variables
inside the settings file first.

Claude Code does NOT expand ${VAR}/$VAR inside settings.json (even when passed
via --settings), so we resolve them here and hand Claude a fully-expanded
temporary settings file. os.path.expandvars handles ${VAR}/$VAR on every OS
(and %VAR% on Windows too), keeping this cross-platform.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SETTINGS_PATH = Path(__file__).resolve().parent / "claude-settings.json"


def main():
    expanded = os.path.expandvars(SETTINGS_PATH.read_text())

    fd, tmp_path = tempfile.mkstemp(suffix=".json", prefix="claude-settings-")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(expanded)

        # shutil.which resolves the real executable (incl. .cmd/.exe on Windows),
        # avoiding any recursion with the shell alias named "claude".
        claude = shutil.which("claude") or "claude"
        cmd = [claude, "--settings", tmp_path, "--enable-auto-mode", *sys.argv[1:]]
        return subprocess.call(cmd)
    finally:
        os.unlink(tmp_path)


if __name__ == "__main__":
    sys.exit(main())
