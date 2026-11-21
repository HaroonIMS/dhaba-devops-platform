#!/usr/bin/env bash
# Checks application services, kitchen-worker heartbeat and Redis queue.
# Usage: check-services.sh [context] [namespaces...]

set -uo pipefail

CONTEXT="${KUBECTL_CONTEXT:-}"
QUEUE_WARNING_THRESHOLD="${QUEUE_WARNING_THRESHOLD:-100}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Validate configuration.
if [[ ! "$QUEUE_WARNING_THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
    echo "FAIL: QUEUE_WARNING_THRESHOLD must be a positive integer"
    exit 2
fi

if [[ ! "$REDIS_PORT" =~ ^[0-9]+$ ]] || (( REDIS_PORT < 1 || REDIS_PORT > 65535 )); then
    echo "FAIL: REDIS_PORT must be between 1 and 65535"
    exit 2
fi

# Optional Kubernetes context.
if [[ $# -gt 0 && "$1" != "staging" && "$1" != "production" ]]; then
    CONTEXT="$1"
    shift
fi

NAMESPACES=("$@")

if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    NAMESPACES=(staging production)
fi

K=(kubectl)

if [[ -n "$CONTEXT" ]]; then
    K+=(--context "$CONTEXT")
fi

SERVICES=(web menu-api orders-api stats-api)

FAILURES=0
WARNINGS=0

ok() {
    echo "OK    $*"
}

warn() {
    echo "WARN  $*"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo "FAIL  $*"
    FAILURES=$((FAILURES + 1))
}

for ns in "${NAMESPACES[@]}"; do

    echo
    echo "========================================"
    echo "SERVICE CHECKS: $ns"
    echo "========================================"

    # Check application Deployments and HTTP health endpoints.
    for svc in "${SERVICES[@]}"; do

        echo
        echo "Checking $svc..."

        if ! "${K[@]}" -n "$ns" get deployment "$svc" >/dev/null 2>&1; then
            fail "$ns $svc Deployment is missing"
            continue
        fi

        READY=$(
            "${K[@]}" -n "$ns" get deployment "$svc" \
                -o jsonpath='{.status.readyReplicas}' 2>/dev/null
        ) || READY=""

        DESIRED=$(
            "${K[@]}" -n "$ns" get deployment "$svc" \
                -o jsonpath='{.spec.replicas}' 2>/dev/null
        ) || DESIRED=""

        READY="${READY:-0}"
        DESIRED="${DESIRED:-1}"

        if [[ ! "$READY" =~ ^[0-9]+$ || ! "$DESIRED" =~ ^[0-9]+$ ]]; then
            fail "$ns $svc Deployment replica status unavailable"
        elif (( READY < DESIRED )); then
            fail "$ns $svc has $READY/$DESIRED ready replicas"
        else
            ok "$ns $svc Deployment ready: $READY/$DESIRED"
        fi

        if ! "${K[@]}" -n "$ns" get service "$svc" >/dev/null 2>&1; then
            fail "$ns $svc Service is missing"
            continue
        fi

        # Prefer the Service port named http; otherwise use its first port.
        PORT=$(
            "${K[@]}" -n "$ns" get service "$svc" \
                -o jsonpath='{.spec.ports[?(@.name=="http")].port}' \
                2>/dev/null
        ) || PORT=""

        if [[ -z "$PORT" ]]; then
            PORT=$(
                "${K[@]}" -n "$ns" get service "$svc" \
                    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null
            ) || PORT=""
        fi

        if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
            fail "$ns $svc Service has no usable port"
            continue
        fi

        OUT=$(
            curl -sS --connect-timeout 3 --max-time 10 \
                -o /dev/null \
                -w "%{http_code} %{time_total}" \
                "http://$svc.$ns.svc.cluster.local:$PORT/health" \
                2>/dev/null
        ) || true

        CODE="${OUT%% *}"
        TIME="${OUT##* }"

        if [[ "$CODE" =~ ^2[0-9][0-9]$ ]]; then
            if awk "BEGIN {exit !($TIME > 1.0)}"; then
                warn "$ns $svc healthy but slow: ${TIME}s"
            else
                ok "$ns $svc healthy (${TIME}s)"
            fi
        else
            fail "$ns $svc health check returned '${CODE:-no response}'"
        fi

    done

    # Check Redis and kitchen-worker heartbeat.
    echo
    echo "========== REDIS AND WORKER =========="

    REDIS_HOST="redis.${ns}.svc.cluster.local"

    if ! command -v redis-cli >/dev/null 2>&1; then
        fail "redis-cli is not installed in the monitoring container"
        continue
    fi

    REDIS_PING=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
            --connect-timeout 3 --no-auth-warning PING 2>/dev/null
    ) || REDIS_PING=""

    if [[ "$REDIS_PING" != "PONG" ]]; then
        fail "$ns Redis is unavailable"
        continue
    fi

    ok "$ns Redis is responding"

    # Check kitchen-worker heartbeat.
    if "${K[@]}" -n "$ns" get deployment kitchen-worker \
        >/dev/null 2>&1; then

        BEAT=$(
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
                --connect-timeout 3 --no-auth-warning TTL worker:heartbeat 2>/dev/null
        ) || BEAT=""

        if [[ "$BEAT" =~ ^[0-9]+$ ]] && (( BEAT > 0 )); then
            ok "$ns kitchen-worker heartbeat present (${BEAT}s TTL)"
        elif [[ "$BEAT" == "-1" ]]; then
            fail "$ns worker heartbeat has no expiry"
        else
            fail "$ns kitchen-worker heartbeat missing or expired"
        fi

    else
        fail "$ns kitchen-worker Deployment is missing"
    fi

    # Check pending orders.
    QLEN=$(
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
            --connect-timeout 3 --no-auth-warning LLEN orders:queue 2>/dev/null
    ) || QLEN=""

    if [[ "$QLEN" =~ ^[0-9]+$ ]]; then
        if (( QLEN >= QUEUE_WARNING_THRESHOLD )); then
            fail "$ns orders queue threshold exceeded: $QLEN pending orders"
        else
            ok "$ns orders queue length: $QLEN"
        fi
    else
        fail "$ns orders queue length unavailable"
    fi

done

echo
echo "========================================"
echo "       SERVICE CHECK SUMMARY"
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
