#!/bin/sh
set -eu

STATE_FILE=/var/tmp/duplicati_stopped_containers.txt
RUNNING_FILE=/var/tmp/duplicati_running_containers.txt

cleanup() {
    rm -f "$RUNNING_FILE"
}
trap cleanup EXIT HUP INT TERM

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
if ! docker ps --quiet > "$RUNNING_FILE"; then
    echo "Error: failed to list running containers" >&2
    exit 1
fi

while IFS= read -r container_id; do
    [ -n "$container_id" ] || continue
    keep_running=$(docker inspect --format '{{ index .Config.Labels "backup.keepRunning" }}' "$container_id")
    if [ "$keep_running" = "true" ]; then
        continue
    fi

    echo "Stopping container $container_id"
    if docker stop "$container_id" >/dev/null; then
        echo "$container_id" >> "$STATE_FILE"
    else
        echo "Error: failed to stop container $container_id" >&2
        exit 1
    fi
done < "$RUNNING_FILE"

echo "Container shutdown complete; state recorded in $STATE_FILE"
