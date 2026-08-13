#!/usr/bin/env bash
# cleanup_catalogs.sh — safely tear down catalogs this run created.
# Reads the marker written during setup, disassociates each created catalog
# from the run's engine, then deletes the catalog. Reused catalogs are
# never touched. Underlying buckets are never touched.
#
# Requires (env): WATSONX_HOSTNAME, WATSONX_INSTANCE_ID, LAKEHOUSE_API_VERSION, AUTH_TOKEN
# Requires: marker_utils.sh sourced by caller OR available at ../pipeline/marker_utils.sh
#
# Usage: bash cleanup_catalogs.sh <marker_path>

set -euo pipefail

# NOTE: the endpoint paths below are best-guess (per the task-5 brief) and
# isolated to _disassociate_catalog / _delete_catalog so they can be
# corrected with a one-line edit once the team lead confirms the real API.
#
# _pipeline_curl is only defined here if the caller hasn't already defined
# it (e.g. a bats test overriding it with a mock before sourcing this file).
if ! declare -F _pipeline_curl >/dev/null 2>&1; then
    _pipeline_curl() {
        # method path
        local method=$1
        local path=$2
        curl -s -k -X "$method" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "LhInstanceId: $WATSONX_INSTANCE_ID" \
            "${WATSONX_HOSTNAME%/}${path}"
    }
fi

_disassociate_catalog() {
    local engine_id=$1
    local catalog=$2
    echo "[cleanup] disassociating $catalog from engine $engine_id" >&2
    _pipeline_curl DELETE "/lakehouse/api/${LAKEHOUSE_API_VERSION}/${WATSONX_INSTANCE_ID}/spark_engines/${engine_id}/catalogs/${catalog}"
}

_delete_catalog() {
    local catalog=$1
    echo "[cleanup] deleting catalog $catalog" >&2
    _pipeline_curl DELETE "/lakehouse/api/${LAKEHOUSE_API_VERSION}/${WATSONX_INSTANCE_ID}/catalogs/${catalog}"
}

cleanup_catalogs() {
    local marker_path=$1
    if [[ ! -f "$marker_path" ]]; then
        echo "error: marker file not found: $marker_path" >&2
        return 1
    fi

    # marker_utils functions may already be sourced; if not, source them
    if ! declare -F marker_get_engine_id >/dev/null 2>&1; then
        # shellcheck source=pipeline/marker_utils.sh
        source "$(dirname "${BASH_SOURCE[0]}")/marker_utils.sh"
    fi

    local engine_id
    engine_id=$(marker_get_engine_id "$marker_path")

    if [[ -z "$engine_id" ]]; then
        echo "[cleanup] no engine recorded, nothing to disassociate" >&2
    fi

    while IFS= read -r catalog; do
        [[ -z "$catalog" ]] && continue
        if [[ -n "$engine_id" ]]; then
            _disassociate_catalog "$engine_id" "$catalog" || \
                echo "[cleanup] warn: disassociate failed for $catalog (continuing)" >&2
        fi
        _delete_catalog "$catalog" || \
            echo "[cleanup] warn: delete failed for $catalog (continuing)" >&2
    done < <(marker_get_catalogs_created "$marker_path")
}

# Run when invoked directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cleanup_catalogs "${1:-}"
fi
