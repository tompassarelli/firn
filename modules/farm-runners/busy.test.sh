#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/busy.sh"

farm_podman() {
  case "$1:$2" in
    top:farm-worker) printf 'ARGS\n./bin/Runner.Listener run\n/home/runner/bin/Runner.Worker spawnclient 1 2\n' ;;
    top:farm-*) printf 'ARGS\n./bin/Runner.Listener run\n' ;;
    logs:farm-acknowledged) printf 'Listening for Jobs\nAcknowledging runner request 34fb995d\n' ;;
    logs:farm-running) printf 'Listening for Jobs\nRunning job: clean-room\n' ;;
    logs:farm-idle) printf 'Connected to GitHub\nListening for Jobs\n' ;;
  esac
}

busy worker
busy acknowledged
busy running
! busy idle
! busy missing
