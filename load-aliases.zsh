SCRIPT_DIR="${0:a:h}"

eval "$(python3 "$SCRIPT_DIR/load_aliases.py" sh "$SCRIPT_DIR/aliases.json")"
