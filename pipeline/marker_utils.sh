#!/usr/bin/env bash
# marker_utils.sh — record what a pipeline run created for later cleanup.
# All functions require jq on PATH.

marker_init() {
    local marker_path=$1
    local run_id=$2
    jq -n \
        --arg run_id "$run_id" \
        '{run_id: $run_id, engine_id: "", engine_created_by_this_run: false, catalogs_created: [], catalogs_reused: []}' \
        > "$marker_path"
}

marker_record_engine() {
    local marker_path=$1
    local engine_id=$2
    local tmp
    tmp=$(mktemp)
    jq --arg eid "$engine_id" \
        '.engine_id = $eid | .engine_created_by_this_run = true' \
        "$marker_path" > "$tmp" \
        && mv "$tmp" "$marker_path" \
        || { rm -f "$tmp"; return 1; }
}

marker_record_catalog_created() {
    local marker_path=$1
    local catalog=$2
    local tmp
    tmp=$(mktemp)
    jq --arg c "$catalog" '.catalogs_created += [$c]' "$marker_path" > "$tmp" \
        && mv "$tmp" "$marker_path" \
        || { rm -f "$tmp"; return 1; }
}

marker_record_catalog_reused() {
    local marker_path=$1
    local catalog=$2
    local tmp
    tmp=$(mktemp)
    jq --arg c "$catalog" '.catalogs_reused += [$c]' "$marker_path" > "$tmp" \
        && mv "$tmp" "$marker_path" \
        || { rm -f "$tmp"; return 1; }
}

marker_get_catalogs_created() {
    local marker_path=$1
    jq -r '.catalogs_created[]' "$marker_path"
}

marker_get_engine_id() {
    local marker_path=$1
    jq -r '.engine_id // ""' "$marker_path"
}
