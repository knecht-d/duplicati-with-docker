ARG DUPLICATI_VERSION=2.4.0.0-stable
FROM duplicati/duplicati:${DUPLICATI_VERSION}@sha256:eb0c1298a1974048332745b393897ae3cc1c20258e4fc26a796f2b5d75eb6218

LABEL backup.keepRunning="true"

RUN set -eux; \
    if command -v apk >/dev/null 2>&1; then \
        apk add --no-cache docker-cli ca-certificates; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update; \
        if apt-cache show docker-cli >/dev/null 2>&1; then \
            apt-get install -y --no-install-recommends docker-cli ca-certificates; \
        else \
            apt-get install -y --no-install-recommends docker.io ca-certificates; \
        fi; \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "Unsupported base image: cannot install Docker CLI" >&2; \
        exit 1; \
    fi

COPY hooks/ /hooks/
RUN chmod 0755 /hooks/stop_containers.sh /hooks/start_containers.sh
