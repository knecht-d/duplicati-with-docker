#!/bin/sh
set -eu

STATE_FILE=/var/tmp/duplicati_stopped_containers.txt
RUNNING_FILE=/var/tmp/duplicati_running_containers.txt

cleanup() {
    rm -f "$RUNNING_FILE"
}
trap cleanup EXIT HUP INT TERM

rollback() {
    rollback_failed=0

    echo "Shutdown failed; restarting containers stopped by this hook" >&2
    while IFS= read -r stopped_id; do
        [ -n "$stopped_id" ] || continue
        echo "Restarting container $stopped_id during rollback" >&2
        if ! docker start "$stopped_id" >/dev/null; then
            echo "Error: failed to restart container $stopped_id during rollback" >&2
            rollback_failed=1
        fi
    done < "$STATE_FILE"

    if [ "$rollback_failed" -eq 0 ]; then
        rm -f "$STATE_FILE"
        echo "Rollback complete; all containers stopped by this hook were restarted" >&2
    else
        echo "Error: automatic rollback was incomplete; state retained in $STATE_FILE for manual recovery" >&2
    fi

    exit 1
}

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker CLI is not available" >&2
    exit 1
fi

if [ ! -S /var/run/docker.sock ]; then
    echo "Error: Docker socket is not available at /var/run/docker.sock" >&2
    exit 1
fi

if [ -e "$STATE_FILE" ]; then
    echo "Error: state file already exists: $STATE_FILE" >&2
    echo "Run the post-backup hook or resolve it manually before starting another backup" >&2
    exit 1
fi

: > "$STATE_FILE"
if ! docker ps --no-trunc --quiet > "$RUNNING_FILE"; then
    echo "Error: failed to list running containers" >&2
    exit 1
fi

while IFS= read -r container_id; do
    [ -n "$container_id" ] || continue
    if ! keep_running=$(docker inspect --format '{{ index .Config.Labels "backup.keepRunning" }}' "$container_id"); then
        echo "Error: failed to inspect container $container_id" >&2
        rollback
    fi
    if [ "$keep_running" = "true" ]; then
        continue
    fi

    echo "Stopping container $container_id"
    if docker stop "$container_id" >/dev/null; then
        echo "$container_id" >> "$STATE_FILE"
    else
        echo "Error: failed to stop container $container_id" >&2
        rollback
    fi
done < "$RUNNING_FILE"

echo "Container shutdown complete; state recorded in $STATE_FILE"
