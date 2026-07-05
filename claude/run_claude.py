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

HERE = Path(__file__).resolve().parent
SETTINGS_PATH = HERE / "claude-settings.json"

# Deployment-specific MCP servers (with their auth tokens) live outside this
# shared repo. An environment defining CLAUDE_MCP_CONFIG points us at its MCP
# config file; when unset or missing we simply launch without it.
_MCP_CONFIG_ENV = os.environ.get("CLAUDE_MCP_CONFIG")
MCP_CONFIG_PATH = Path(_MCP_CONFIG_ENV) if _MCP_CONFIG_ENV else None


def expand_to_tempfile(src: Path, prefix: str) -> str:
    """Write an env-var-expanded copy of `src` to a temp file, return its path."""
    fd, tmp_path = tempfile.mkstemp(suffix=".json", prefix=prefix)
    with os.fdopen(fd, "w") as f:
        f.write(os.path.expandvars(src.read_text()))
    return tmp_path


def main():
    tmp_files = []
    try:
        settings_tmp = expand_to_tempfile(SETTINGS_PATH, "claude-settings-")
        tmp_files.append(settings_tmp)

        # shutil.which resolves the real executable (incl. .cmd/.exe on Windows),
        # avoiding any recursion with the shell alias named "claude".
        claude = shutil.which("claude") or "claude"
        cmd = [claude, "--settings", settings_tmp, "--enable-auto-mode"]

        if MCP_CONFIG_PATH and MCP_CONFIG_PATH.exists():
            mcp_tmp = expand_to_tempfile(MCP_CONFIG_PATH, "claude-mcp-")
            tmp_files.append(mcp_tmp)
            cmd += ["--mcp-config", mcp_tmp]

        cmd += sys.argv[1:]
        return subprocess.call(cmd)
    finally:
        for path in tmp_files:
            os.unlink(path)


if __name__ == "__main__":
    sys.exit(main())
