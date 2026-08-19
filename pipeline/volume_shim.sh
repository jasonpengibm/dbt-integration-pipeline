#!/usr/bin/env bash
# volume_shim.sh — clean replacement for get_available_volume_id in run_catalog_tests.sh.
#
# The original implementation in run_catalog_tests.sh calls log_info/log_warning
# (which write to stdout) inside get_available_volume_id. Because the caller
# captures the function's stdout with $(...), those log lines get embedded in
# the volume_id variable, corrupting the JSON payload sent to the engine API.
#
# This shim redefines the function so only the numeric ID (or nothing) goes to
# stdout; all diagnostic messages go to stderr. It is sourced by the pipeline
# before invoking the given script, which re-sources this via export -f.
#
# Usage (pipeline injects before calling the given script):
#   source pipeline/volume_shim.sh
#   export -f get_available_volume_id
#   bash scripts/run_catalog_tests.sh

get_available_volume_id() {
    local volume_name="${1:-spark-engine-volume}"

    # If the pipeline already resolved the ID, return it directly.
    if [ -n "${SPARK_ENGINE_VOLUME_ID:-}" ]; then
        echo "[volume-shim] using pre-resolved SPARK_ENGINE_VOLUME_ID" >&2
        echo "$SPARK_ENGINE_VOLUME_ID"
        return 0
    fi

    # Auth token must already be set (pipeline pre-authenticates).
    if [ -z "${AUTH_TOKEN:-}" ]; then
        echo "[volume-shim] ERROR: AUTH_TOKEN not set" >&2
        return 1
    fi

    local api_url="${WATSONX_HOSTNAME}/lakehouse/api/${LAKEHOUSE_API_VERSION:-v3}/${WATSONX_INSTANCE_ID}/cpd/spark_instances"
    echo "[volume-shim] looking up volume '${volume_name}' via ${api_url}" >&2

    local response
    response=$(curl -s -k -X GET "${api_url}" \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" 2>/dev/null)

    local full_display_name="cpd-instance::${volume_name}"
    local volume_id
    volume_id=$(echo "$response" \
        | jq -r ".volumes[]? | select(.display_name == \"${full_display_name}\") | .instance_id // empty" \
        2>/dev/null | head -n1)

    if [ -n "$volume_id" ]; then
        echo "[volume-shim] found '${volume_name}' → ${volume_id}" >&2
        echo "$volume_id"
        return 0
    else
        echo "[volume-shim] '${volume_name}' not found; engine will be created with a new volume" >&2
        return 1
    fi
}
