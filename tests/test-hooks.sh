#!/bin/sh
set -eu

IMAGE=${IMAGE:-duplicati-with-docker:test}
TEST_PREFIX=duplicati-hooks-test-$$
RUNNING_CONTAINER=${TEST_PREFIX}-running
KEPT_CONTAINER=${TEST_PREFIX}-kept
STOPPED_CONTAINER=${TEST_PREFIX}-stopped
DUPLICATI_CONTAINER=${TEST_PREFIX}-duplicati
ROLLBACK_CONTAINER=${TEST_PREFIX}-rollback
STATE_FILE=/var/tmp/duplicati_stopped_containers.txt
TEST_TMP_DIR=

cleanup() {
    docker rm -f \
        "$RUNNING_CONTAINER" \
        "$KEPT_CONTAINER" \
        "$STOPPED_CONTAINER" \
        "$DUPLICATI_CONTAINER" \
        "$ROLLBACK_CONTAINER" >/dev/null 2>&1 || true
    if [ -n "$TEST_TMP_DIR" ]; then
        rm -rf -- "$TEST_TMP_DIR"
    fi
}
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

is_running() {
    [ "$(docker inspect --format '{{.State.Running}}' "$1")" = "true" ]
}

if ! docker info >/dev/null 2>&1; then
    fail "cannot access the Docker daemon"
fi

existing_containers=$(docker ps --quiet)
if [ -n "$existing_containers" ]; then
    echo "FAIL: integration tests require a clean Docker daemon / CI environment" >&2
    echo "Refusing to modify these existing running containers:" >&2
    docker ps --format '  {{.ID}}  {{.Names}}' >&2
    exit 1
fi

TEST_TMP_DIR=$(mktemp -d)
cat > "$TEST_TMP_DIR/docker" <<'EOF'
#!/bin/sh
set -eu

if [ "${1:-}" = "stop" ]; then
    if [ -e /var/tmp/duplicati_test_stop_seen ]; then
        echo "Intentional docker stop failure for rollback test" >&2
        exit 1
    fi
    : > /var/tmp/duplicati_test_stop_seen
fi

exec /usr/bin/docker "$@"
EOF
chmod 0755 "$TEST_TMP_DIR/docker"

docker run -d --name "$RUNNING_CONTAINER" busybox:1.37.0 sleep 3600 >/dev/null
docker run -d --name "$KEPT_CONTAINER" \
    --label backup.keepRunning=true busybox:1.37.0 sleep 3600 >/dev/null
docker create --name "$STOPPED_CONTAINER" busybox:1.37.0 sleep 3600 >/dev/null
docker run -d --name "$DUPLICATI_CONTAINER" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$TEST_TMP_DIR:/tmp/test-bin:ro" \
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

docker run -d --name "$ROLLBACK_CONTAINER" busybox:1.37.0 sleep 3600 >/dev/null

if docker exec \
    -e PATH=/tmp/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$DUPLICATI_CONTAINER" /hooks/stop_containers.sh; then
    fail "pre-backup hook succeeded despite the intentional stop failure"
fi

is_running "$RUNNING_CONTAINER" || fail "first stopped container was not restored by rollback"
is_running "$ROLLBACK_CONTAINER" || fail "rollback test container is not running"
is_running "$KEPT_CONTAINER" || fail "keep-running container was affected by rollback"
is_running "$STOPPED_CONTAINER" && fail "previously stopped container was started by rollback"

if docker exec "$DUPLICATI_CONTAINER" test -e "$STATE_FILE"; then
    fail "state file was retained after a successful rollback"
fi

echo "Hook integration tests passed"
