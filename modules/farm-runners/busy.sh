busy() {
  grep -q Runner.Worker < <(farm_podman top "farm-$1" -eo args 2>/dev/null) ||
    grep -qE 'Acknowledging runner request|Running job:' < <(farm_podman logs "farm-$1" 2>&1)
}
