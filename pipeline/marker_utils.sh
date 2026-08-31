#!/usr/bin/env bash
# marker_utils.sh — record what a pipeline run created for later cleanup.

marker_init() {
    local marker_path=$1
    local run_id=$2
    jq -n \
        --arg run_id "$run_id" \
        '{run_id: $run_id, engine_ids: [], catalogs_created: [], catalogs_reused: []}' \
        > "$marker_path"
}

# Append an engine id to the marker. The given run_catalog_tests.sh always creates
# both a standard and an authz engine per run, so we may call this more than once.
marker_record_engine() {
    local marker_path=$1
    local engine_id=$2
    [[ -z "$engine_id" ]] && return 0
    local tmp
    tmp=$(mktemp)
    if ! jq --arg eid "$engine_id" \
        '.engine_ids |= (. + [$eid] | unique)' \
        "$marker_path" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$marker_path"
}

# Record a catalog that was freshly created this run 
marker_record_catalog_created() {
    local marker_path=$1
    local catalog=$2
    local tmp
    tmp=$(mktemp)
    if ! jq --arg c "$catalog" '.catalogs_created += [$c]' "$marker_path" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$marker_path"
}

# Record a catalog that already existed and was reused 
marker_record_catalog_reused() {
    local marker_path=$1
    local catalog=$2
    local tmp
    tmp=$(mktemp)
    if ! jq --arg c "$catalog" '.catalogs_reused += [$c]' "$marker_path" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$marker_path"
}

# Print each created catalog name on its own line (used by cleanup to know what to delete).
marker_get_catalogs_created() {
    local marker_path=$1
    jq -r '.catalogs_created[]' "$marker_path"
}

# Print each recorded engine ID on its own line.
marker_get_engine_ids() {
    local marker_path=$1
    jq -r '.engine_ids[]?' "$marker_path"
}

# Return 0 if the given catalog was reused (not created) this run.
marker_has_catalog_reused() {
    local marker_path=$1
    local catalog=$2
    jq -e --arg c "$catalog" '.catalogs_reused | index($c)' "$marker_path" >/dev/null 2>&1
}
