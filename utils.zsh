function run-until-success() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: run-until-success <command> [args...]"
    return 1
  fi

  until "$@"; do
    echo "Command failed, retrying..."
    sleep 1
  done
  echo "Command succeeded!"
}
