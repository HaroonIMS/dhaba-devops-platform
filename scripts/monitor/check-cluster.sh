#!/usr/bin/env bash
# Checks node readiness, pod health, node resources,
# persistent volume claims, and Kubernetes warning events.

set -uo pipefail

CONTEXT="${1:-}"
K=(kubectl)
[[ -n "$CONTEXT" ]] && K+=(--context "$CONTEXT")

FAILURES=0

ok()   { echo "OK    $*"; }
warn() { echo "WARN  $*"; }
fail() { echo "FAIL  $*"; FAILURES=$((FAILURES + 1)); }

echo "========== CLUSTER HEALTH =========="

# 1. Node readiness
if NODES=$("${K[@]}" get nodes --no-headers 2>&1); then
    if [[ -z "$NODES" ]]; then
        fail "cluster returned no nodes"
    else
        NOT_READY=$(awk '$2 != "Ready" {print $1}' <<< "$NODES")
        if [[ -z "$NOT_READY" ]]; then
            ok "all nodes Ready"
        else
            fail "nodes not Ready: $(tr '\n' ' ' <<< "$NOT_READY")"
        fi
    fi
else
    fail "could not retrieve nodes: $NODES"
fi

# 2. Crashing pods and repeated restarts
if PODS=$("${K[@]}" get pods -A --no-headers 2>&1); then
    BAD_PODS=$(awk '
        $4 ~ /CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|Error/ {
            print $1 "/" $2 " (" $4 ")"
        }
        $5+0 >= 5 && $4 == "Running" {
            print $1 "/" $2 " (restarts=" $5 ")"
        }
    ' <<< "$PODS")

    if [[ -z "$BAD_PODS" ]]; then
        ok "no crashing or stuck pods"
    else
        fail "problem pods: $(tr '\n' ' ' <<< "$BAD_PODS")"
    fi
else
    fail "could not retrieve pods: $PODS"
fi

# 3. Node CPU and memory (requires metrics-server)
if TOP=$("${K[@]}" top nodes --no-headers 2>&1); then
    if [[ -z "$TOP" ]]; then
        warn "node metrics returned no data"
    else
        while read -r name _cpu cpu_pct _mem mem_pct; do
            cpu_pct=${cpu_pct%\%}
            mem_pct=${mem_pct%\%}

            if (( cpu_pct >= 90 || mem_pct >= 90 )); then
                fail "$name high use: CPU ${cpu_pct}% MEM ${mem_pct}%"
            elif (( cpu_pct >= 75 || mem_pct >= 75 )); then
                warn "$name busy: CPU ${cpu_pct}% MEM ${mem_pct}%"
            else
                ok "$name CPU ${cpu_pct}% MEM ${mem_pct}%"
            fi
        done <<< "$TOP"
    fi
else
    warn "node metrics unavailable: $TOP"
fi

# 4. Persistent volume claims
if PVCS=$("${K[@]}" get pvc -A --no-headers 2>&1); then
    PVC_BAD=$(awk '$3 != "Bound" {print $1 "/" $2 " (" $3 ")"}' <<< "$PVCS")

    if [[ -z "$PVC_BAD" ]]; then
        ok "all persistent volume claims Bound"
    else
        fail "unbound volumes: $(tr '\n' ' ' <<< "$PVC_BAD")"
    fi
else
    fail "could not retrieve PVCs: $PVCS"
fi

# 5. Warning events
if EVENTS=$("${K[@]}" get events -A --field-selector type=Warning --no-headers 2>&1); then
    WARNING_COUNT=$(awk 'NF {count++} END {print count+0}' <<< "$EVENTS")

    if (( WARNING_COUNT == 0 )); then
        ok "no warning events"
    else
        warn "$WARNING_COUNT warning event(s) in the cluster"
    fi
else
    fail "could not retrieve warning events: $EVENTS"
fi

echo
if (( FAILURES > 0 )); then
    echo "RESULT: $FAILURES check(s) failed"
    exit 1
fi

echo "RESULT: no failures"
