#!/bin/sh
set -eu

IMAGE=${IMAGE:-duplicati-with-docker:test}
TEST_PREFIX=duplicati-hooks-test-$$
RUNNING_CONTAINER=${TEST_PREFIX}-running
KEPT_CONTAINER=${TEST_PREFIX}-kept
STOPPED_CONTAINER=${TEST_PREFIX}-stopped
DUPLICATI_CONTAINER=${TEST_PREFIX}-duplicati
STATE_FILE=/var/tmp/duplicati_stopped_containers.txt

cleanup() {
    docker rm -f \
        "$RUNNING_CONTAINER" \
        "$KEPT_CONTAINER" \
        "$STOPPED_CONTAINER" \
        "$DUPLICATI_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

is_running() {
    [ "$(docker inspect --format '{{.State.Running}}' "$1")" = "true" ]
}

cleanup

docker run -d --name "$RUNNING_CONTAINER" busybox:1.37.0 sleep 3600 >/dev/null
docker run -d --name "$KEPT_CONTAINER" \
    --label backup.keepRunning=true busybox:1.37.0 sleep 3600 >/dev/null
docker create --name "$STOPPED_CONTAINER" busybox:1.37.0 sleep 3600 >/dev/null
docker run -d --name "$DUPLICATI_CONTAINER" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$IMAGE" sleep 3600 >/dev/null

docker exec "$DUPLICATI_CONTAINER" /hooks/stop_containers.sh

is_running "$RUNNING_CONTAINER" && fail "ordinary running container was not stopped"
is_running "$KEPT_CONTAINER" || fail "keep-running container was stopped"
is_running "$STOPPED_CONTAINER" && fail "previously stopped container was started"
is_running "$DUPLICATI_CONTAINER" || fail "Duplicati container stopped itself"

recorded=$(docker exec "$DUPLICATI_CONTAINER" cat "$STATE_FILE")
running_id=$(docker inspect --format '{{.Id}}' "$RUNNING_CONTAINER")
[ "$recorded" = "$running_id" ] || fail "state file did not contain exactly the stopped container"

docker exec "$DUPLICATI_CONTAINER" /hooks/start_containers.sh

is_running "$RUNNING_CONTAINER" || fail "ordinary container was not restarted"
is_running "$KEPT_CONTAINER" || fail "keep-running container is not running"
is_running "$STOPPED_CONTAINER" && fail "previously stopped container was started"
is_running "$DUPLICATI_CONTAINER" || fail "Duplicati container is not running"

if docker exec "$DUPLICATI_CONTAINER" test -e "$STATE_FILE"; then
    fail "state file was not removed"
fi

echo "Hook integration tests passed"
