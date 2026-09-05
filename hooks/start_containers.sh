#!/bin/sh
set -eu

STATE_FILE=/var/tmp/duplicati_stopped_containers.txt

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker CLI is not available" >&2
    exit 1
fi

if [ ! -S /var/run/docker.sock ]; then
    echo "Error: Docker socket is not available at /var/run/docker.sock" >&2
    exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
    echo "No container state file found; nothing to restart"
    exit 0
fi

while IFS= read -r container_id; do
    [ -n "$container_id" ] || continue
    echo "Restarting container $container_id"
    if ! docker start "$container_id" >/dev/null; then
        echo "Error: failed to restart container $container_id" >&2
        exit 1
    fi
done < "$STATE_FILE"

rm -f "$STATE_FILE"
echo "Recorded containers restarted; state file removed"
