#!/usr/bin/env bash

set -uo pipefail

# Configuration
NAMESPACES=("staging" "production")
QUEUE_WARNING_THRESHOLD="${QUEUE_WARNING_THRESHOLD:-100}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Kubernetes CLI command.
KUBECTL=(kubectl)

if [[ ! "$QUEUE_WARNING_THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
    echo "[FAIL] QUEUE_WARNING_THRESHOLD must be a positive integer"
    exit 2
fi

if [[ ! "$REDIS_PORT" =~ ^[0-9]+$ ]] || (( REDIS_PORT < 1 || REDIS_PORT > 65535 )); then
    echo "[FAIL] REDIS_PORT must be between 1 and 65535"
    exit 2
fi
FAILURES=0
WARNINGS=0

pass() {
    echo "[PASS] $1"
}

warn() {
    echo "[WARN] $1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo "[FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

echo "========================================"
echo "       DATABASE HEALTH MONITOR"
echo "========================================"
echo "Queue warning threshold: $QUEUE_WARNING_THRESHOLD"
echo

for namespace in "${NAMESPACES[@]}"; do

    echo "----------------------------------------"
    echo "Checking namespace: $namespace"
    echo "----------------------------------------"

    # PostgreSQL checks
    echo
    echo "========== POSTGRESQL =========="

    if "${KUBECTL[@]}" -n "$namespace" exec postgres-0 -- \
        pg_isready -U dhaba -d dhaba >/dev/null 2>&1; then
        pass "$namespace PostgreSQL is accepting connections"
    else
        fail "$namespace PostgreSQL is unavailable"
    fi

    # shellcheck disable=SC2016 # Variables expand inside the PostgreSQL container.
    CONNECTIONS=$(
        "${KUBECTL[@]}" -n "$namespace" exec postgres-0 -- \
        sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
        "SELECT count(*) FROM pg_stat_activity;"' 2>/dev/null
    ) || CONNECTIONS=""

    if [[ "$CONNECTIONS" =~ ^[0-9]+$ ]]; then
        pass "$namespace PostgreSQL connections: $CONNECTIONS"
    else
        fail "$namespace PostgreSQL connection count unavailable"
    fi

    # shellcheck disable=SC2016 # Variables expand inside the PostgreSQL container.
    DB_SIZE=$(
        "${KUBECTL[@]}" -n "$namespace" exec postgres-0 -- \
        sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
        "SELECT pg_size_pretty(pg_database_size(current_database()));"' \
        2>/dev/null
    ) || DB_SIZE=""

    if [[ -n "$DB_SIZE" ]]; then
        pass "$namespace PostgreSQL database size: $DB_SIZE"
    else
        fail "$namespace PostgreSQL database size unavailable"
    fi

    # shellcheck disable=SC2016 # Variables expand inside the PostgreSQL container.
    VOLUME_USAGE=$(
        "${KUBECTL[@]}" -n "$namespace" exec postgres-0 -- \
        sh -c 'df -P "$PGDATA" | awk "NR==2 {print \$5}"' 2>/dev/null
    ) || VOLUME_USAGE=""

    if [[ "$VOLUME_USAGE" =~ ^[0-9]+%$ ]]; then
        USAGE=${VOLUME_USAGE%\%}

        if (( USAGE >= 90 )); then
            fail "$namespace PostgreSQL volume usage: $VOLUME_USAGE"
        elif (( USAGE >= 75 )); then
            warn "$namespace PostgreSQL volume usage: $VOLUME_USAGE"
        else
            pass "$namespace PostgreSQL volume usage: $VOLUME_USAGE"
        fi
    else
        fail "$namespace PostgreSQL volume usage unavailable"
    fi

    # Redis checks
    echo
    echo "========== REDIS =========="

    REDIS_HOST="redis.${namespace}.svc.cluster.local"

    if ! command -v redis-cli >/dev/null 2>&1; then
        fail "redis-cli is not installed in the monitoring container"
        continue
    fi

    REDIS_PING=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        --no-auth-warning PING 2>/dev/null
    ) || REDIS_PING=""

    if [[ "$REDIS_PING" == "PONG" ]]; then
        pass "$namespace Redis is responding"
    else
        fail "$namespace Redis is unavailable"
        continue
    fi

    REDIS_MEMORY=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        --no-auth-warning INFO memory 2>/dev/null |
        awk -F: '/^used_memory_human:/ {gsub("\r", "", $2); print $2}'
    )

    if [[ -n "$REDIS_MEMORY" ]]; then
        pass "$namespace Redis memory usage: $REDIS_MEMORY"
    else
        warn "$namespace Redis memory information unavailable"
    fi

    REDIS_LASTSAVE=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        --no-auth-warning LASTSAVE 2>/dev/null
    ) || REDIS_LASTSAVE=""

    if [[ "$REDIS_LASTSAVE" =~ ^[0-9]+$ ]] && (( REDIS_LASTSAVE > 0 )); then
        pass "$namespace Redis last successful save timestamp: $REDIS_LASTSAVE"
    else
        warn "$namespace Redis last save information unavailable"
    fi

    REDIS_CLIENTS=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        --no-auth-warning INFO clients 2>/dev/null |
        awk -F: '/^connected_clients:/ {gsub("\r", "", $2); print $2}'
    )

    if [[ "$REDIS_CLIENTS" =~ ^[0-9]+$ ]]; then
        pass "$namespace Redis connected clients: $REDIS_CLIENTS"
    else
        warn "$namespace Redis client information unavailable"
    fi

    # Kitchen worker heartbeat
    echo
    echo "========== WORKER HEARTBEAT =========="

    HEARTBEAT_TTL=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        --no-auth-warning TTL worker:heartbeat 2>/dev/null
    ) || HEARTBEAT_TTL=""

    if [[ "$HEARTBEAT_TTL" =~ ^-?[0-9]+$ ]]; then
        if (( HEARTBEAT_TTL > 0 )); then
            pass "$namespace kitchen worker heartbeat TTL: ${HEARTBEAT_TTL}s"
        elif (( HEARTBEAT_TTL == -1 )); then
            warn "$namespace worker heartbeat exists without an expiry"
        else
            fail "$namespace kitchen worker heartbeat is missing or expired"
        fi
    else
        fail "$namespace worker heartbeat check failed"
    fi

    # Orders queue length
    echo
    echo "========== ORDERS QUEUE =========="

    QUEUE_LENGTH=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        --no-auth-warning LLEN orders:queue 2>/dev/null
    ) || QUEUE_LENGTH=""

    if [[ "$QUEUE_LENGTH" =~ ^[0-9]+$ ]]; then
        if (( QUEUE_LENGTH >= QUEUE_WARNING_THRESHOLD )); then
            warn "$namespace orders queue reached threshold: $QUEUE_LENGTH pending orders"
        else
            pass "$namespace orders queue length: $QUEUE_LENGTH"
        fi
    else
        fail "$namespace orders queue length unavailable"
    fi

    echo

done

echo "========================================"
echo "       DATABASE CHECK SUMMARY"
echo "========================================"
echo "Failures: $FAILURES"
echo "Warnings: $WARNINGS"

if (( FAILURES > 0 )); then
    echo "RESULT: FAILED"
    exit 1
fi

if (( WARNINGS > 0 )); then
    echo "RESULT: WARNING"
    exit 0
fi

echo "RESULT: ALL CHECKS PASSED"
exit 0
