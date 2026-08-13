#!/usr/bin/env bats

load 'test_helpers'

setup() {
    setup_pipeline_test_env
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../pipeline/marker_utils.sh"
    MARKER="$TEST_TMPDIR/marker.json"
}

teardown() {
    teardown_pipeline_test_env
}

@test "marker_init creates a fresh marker with expected keys" {
    marker_init "$MARKER" "run-1"
    [ -f "$MARKER" ]
    run jq -r '.run_id' "$MARKER"
    [ "$output" = "run-1" ]
    run jq -r '.engine_created_by_this_run' "$MARKER"
    [ "$output" = "false" ]
    run jq -r '.catalogs_created | length' "$MARKER"
    [ "$output" = "0" ]
}

@test "marker_record_engine sets engine_id and engine_created_by_this_run" {
    marker_init "$MARKER" "run-1"
    marker_record_engine "$MARKER" "eng-abc"
    run jq -r '.engine_id' "$MARKER"
    [ "$output" = "eng-abc" ]
    run jq -r '.engine_created_by_this_run' "$MARKER"
    [ "$output" = "true" ]
}

@test "marker_record_catalog_created appends to catalogs_created" {
    marker_init "$MARKER" "run-1"
    marker_record_catalog_created "$MARKER" "iceberg_data"
    marker_record_catalog_created "$MARKER" "hudi_data"
    run jq -r '.catalogs_created | length' "$MARKER"
    [ "$output" = "2" ]
    run jq -r '.catalogs_created[0]' "$MARKER"
    [ "$output" = "iceberg_data" ]
    run jq -r '.catalogs_created[1]' "$MARKER"
    [ "$output" = "hudi_data" ]
}

@test "marker_record_catalog_reused appends to catalogs_reused" {
    marker_init "$MARKER" "run-1"
    marker_record_catalog_reused "$MARKER" "delta_data"
    run jq -r '.catalogs_reused[0]' "$MARKER"
    [ "$output" = "delta_data" ]
}

@test "marker_get_catalogs_created echoes newline-separated names" {
    marker_init "$MARKER" "run-1"
    marker_record_catalog_created "$MARKER" "iceberg_data"
    marker_record_catalog_created "$MARKER" "hudi_data"
    run marker_get_catalogs_created "$MARKER"
    [ "$status" -eq 0 ]
    printf '%s\n' "iceberg_data" "hudi_data" | diff - <(printf '%s\n' "$output")
}

@test "marker_get_engine_id echoes empty string when no engine recorded" {
    marker_init "$MARKER" "run-1"
    run marker_get_engine_id "$MARKER"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "marker_get_engine_id echoes engine_id when recorded" {
    marker_init "$MARKER" "run-1"
    marker_record_engine "$MARKER" "eng-xyz"
    run marker_get_engine_id "$MARKER"
    [ "$output" = "eng-xyz" ]
}
