#!/usr/bin/env bash
# volume_shim.sh — replacement for get_available_volume_id in run_catalog_tests.sh.

# Usage (pipeline injects before calling the given script):
#   source pipeline/volume_shim.sh
#   export -f get_available_volume_id
#   bash scripts/run_catalog_tests.sh

get_available_volume_id() {
    # If the pipeline already resolved the ID, skip lookups.
    if [ -n "${SPARK_ENGINE_VOLUME_ID:-}" ]; then
        echo "[volume-shim] using pre-resolved SPARK_ENGINE_VOLUME_ID=${SPARK_ENGINE_VOLUME_ID}" >&2
        echo "$SPARK_ENGINE_VOLUME_ID"
        return 0
    fi

    if [ -z "${AUTH_TOKEN:-}" ]; then
        echo "[volume-shim] ERROR: AUTH_TOKEN not set" >&2
        return 1
    fi

    local volume_name="${SPARK_ENGINE_VOLUME_NAME:-}"
    if [ -z "$volume_name" ]; then
        echo "[volume-shim] ERROR: SPARK_ENGINE_VOLUME_NAME not set" >&2
        return 1
    fi

    local api_url="${WATSONX_HOSTNAME}/lakehouse/api/${LAKEHOUSE_API_VERSION:-v3}/${WATSONX_INSTANCE_ID}/cpd/spark_instances"

    local response
    response=$(curl -s -k -X GET "${api_url}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" 2>/dev/null)

    local volume_id
    volume_id=$(echo "$response" \
        | jq -r --arg n "cpd-instance::${volume_name}" \
            '.volumes[]? | select(.display_name == $n) | .instance_id // empty' \
        2>/dev/null | head -n1)
    if [ -n "$volume_id" ]; then
        echo "[volume-shim] using '${volume_name}' -> ${volume_id}" >&2
        echo "$volume_id"
        return 0
    fi

    echo "[volume-shim] ERROR: volume '${volume_name}' not found on this cluster" >&2
    return 1
}
