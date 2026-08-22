#!/usr/bin/env bash
# volume_shim.sh — replacement for get_available_volume_id in run_catalog_tests.sh.

# Usage (pipeline injects before calling the given script):
#   source pipeline/volume_shim.sh
#   export -f get_available_volume_id
#   bash scripts/run_catalog_tests.sh

get_available_volume_id() {
    # If the pipeline already resolved the ID, return it directly — skip all lookups.
    if [ -n "${SPARK_ENGINE_VOLUME_ID:-}" ]; then
        echo "[volume-shim] using pre-resolved SPARK_ENGINE_VOLUME_ID=${SPARK_ENGINE_VOLUME_ID}" >&2
        echo "$SPARK_ENGINE_VOLUME_ID"
        return 0
    fi

    # Auth token must already be set (pipeline pre-authenticates).
    if [ -z "${AUTH_TOKEN:-}" ]; then
        echo "[volume-shim] ERROR: AUTH_TOKEN not set" >&2
        return 1
    fi

    local api_url="${WATSONX_HOSTNAME}/lakehouse/api/${LAKEHOUSE_API_VERSION:-v3}/${WATSONX_INSTANCE_ID}/cpd/spark_instances"

    local response
    response=$(curl -s -k -X GET "${api_url}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" 2>/dev/null)

    # Preference order: spark-vol (Bound, managed-nfs-storage) before
    # spark-engine-volume (Pending, nfs-client provisioner absent on this cluster).
    local volume_id=""
    for candidate in spark-vol spark-engine-volume; do
        volume_id=$(echo "$response" \
            | jq -r --arg n "cpd-instance::${candidate}" \
                '.volumes[]? | select(.display_name == $n) | .instance_id // empty' \
            2>/dev/null | head -n1)
        if [ -n "$volume_id" ]; then
            echo "[volume-shim] using '${candidate}' -> ${volume_id}" >&2
            echo "$volume_id"
            return 0
        fi
    done

    echo "[volume-shim] ERROR: no usable volume found (tried: spark-vol, spark-engine-volume)" >&2
    return 1
}
