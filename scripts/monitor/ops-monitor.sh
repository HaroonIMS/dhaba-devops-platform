#!/usr/bin/env bash
# Runs monitoring checks and reports results to Kubernetes Job logs.
# Sends a healthy summary every 30 minutes.

set -uo pipefail

NAMESPACE="${OPS_NAMESPACE:-ops}"
CONFIGMAP="${OPS_CONFIGMAP:-ops-monitor-state}"
SUMMARY_INTERVAL="${SUMMARY_INTERVAL:-1800}"

FAILURES=0
REPORT=""

if [[ ! "$SUMMARY_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: SUMMARY_INTERVAL must be a positive integer"
    exit 1
fi

# Check required tools.
for tool in kubectl jq curl date; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required tool is missing: $tool"
        exit 1
    fi
done

ok() {
    echo "OK    $*"
}

fail() {
    echo "FAIL  $*"
}

# Execute a monitoring script and capture its output.
run_check() {
    local name="$1"
    local script="$2"
    local output
    local rc

    echo
    echo "Running $name..."

    if [[ ! -x "$script" ]]; then
        output="Monitoring script missing or not executable: $script"
        rc=1
    else
        output=$("$script" 2>&1)
        rc=$?
    fi

    REPORT+=$'\n'"--- $name ---"$'\n'"$output"$'\n'

    if (( rc != 0 )); then
        FAILURES=$((FAILURES + 1))
        fail "$name reported a problem"
    else
        ok "$name completed successfully"
    fi
}

# Run all monitoring checks.
run_check "Cluster checks" "/opt/monitor/check-cluster.sh"
run_check "Database checks" "/opt/monitor/check-databases.sh"
run_check "Service checks" "/opt/monitor/check-services.sh"

NOW=$(date +%s)

if (( FAILURES > 0 )); then
    NEW_STATE="FAIL"
else
    NEW_STATE="OK"
fi

echo
echo "Monitoring failures: $FAILURES"
echo "New monitoring state: $NEW_STATE"

# Read persisted monitoring state.
if ! STATE_DATA=$(
    kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" \
        -o jsonpath='{.data.state}{"|"}{.data.last_summary}' 2>&1
); then
    echo "ERROR: Could not read monitoring state from ConfigMap"
    echo "$STATE_DATA"
    exit 1
fi

PREVIOUS_STATE="${STATE_DATA%%|*}"
LAST_SUMMARY="${STATE_DATA#*|}"

if [[ "$PREVIOUS_STATE" != "OK" && "$PREVIOUS_STATE" != "FAIL" ]]; then
    echo "ERROR: Invalid monitoring state"
    exit 1
fi

if [[ ! "$LAST_SUMMARY" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid last_summary value"
    exit 1
fi

# Update monitoring state in Kubernetes.
update_state() {
    local state="$1"
    local summary_time="$2"
    local patch

    patch=$(jq -n \
        --arg state "$state" \
        --arg summary "$summary_time" \
        '{data: {state: $state, last_summary: $summary}}'
    ) || return 1

    kubectl -n "$NAMESPACE" patch configmap "$CONFIGMAP" \
        --type merge \
        -p "$patch" >/dev/null
}

# Print complete check results to Kubernetes Job logs.
echo
echo "========== MONITORING REPORT =========="
printf '%s\n' "$REPORT"

# Handle state transitions and periodic healthy summaries.
if [[ "$NEW_STATE" == "FAIL" && "$PREVIOUS_STATE" != "FAIL" ]]; then

    echo "FAILURE DETECTED: monitoring state changed from OK to FAIL."

    if ! update_state "$NEW_STATE" "$LAST_SUMMARY"; then
        echo "ERROR: Could not update monitoring state"
        exit 1
    fi

elif [[ "$NEW_STATE" == "OK" && "$PREVIOUS_STATE" == "FAIL" ]]; then

    echo "RECOVERY DETECTED: monitoring state changed from FAIL to OK."

    if ! update_state "$NEW_STATE" "$LAST_SUMMARY"; then
        echo "ERROR: Could not update monitoring state"
        exit 1
    fi

elif [[ "$NEW_STATE" == "OK" ]]; then

    if (( NOW - LAST_SUMMARY >= SUMMARY_INTERVAL )); then
        echo "Healthy monitoring summary is due."

        if ! update_state "$NEW_STATE" "$NOW"; then
            echo "ERROR: Could not update monitoring state"
            exit 1
        fi
    else
        echo "Healthy. No periodic summary is due yet."

        if ! update_state "$NEW_STATE" "$LAST_SUMMARY"; then
            echo "ERROR: Could not update monitoring state"
            exit 1
        fi
    fi

else

    echo "FAILURE CONTINUES: no new state transition."

    if ! update_state "$NEW_STATE" "$LAST_SUMMARY"; then
        echo "ERROR: Could not update monitoring state"
        exit 1
    fi

fi

echo
echo "Monitoring completed. State: $NEW_STATE"
