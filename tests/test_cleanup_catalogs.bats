#!/usr/bin/env bats

load 'test_helpers'

setup() {
    setup_pipeline_test_env
    export WATSONX_HOSTNAME=https://cpd.example.com
    export WATSONX_INSTANCE_ID=inst-1
    export LAKEHOUSE_API_VERSION=v3
    export AUTH_TOKEN=fake-token
    MARKER="$TEST_TMPDIR/marker.json"
    CALLS_LOG="$TEST_TMPDIR/curl_calls.log"
    export CALLS_LOG
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../pipeline/marker_utils.sh"
}

teardown() {
    teardown_pipeline_test_env
}

# Helper: run cleanup_catalogs.sh with a mocked _pipeline_curl that records calls to $CALLS_LOG
run_cleanup_with_mock() {
    bash -c '
        # shellcheck disable=SC1091
        source "'"${BATS_TEST_DIRNAME}"'/../pipeline/marker_utils.sh"
        _pipeline_curl() {
            echo "$*" >> "$CALLS_LOG"
            return 0
        }
        export -f _pipeline_curl
        # shellcheck disable=SC1091
        source "'"${BATS_TEST_DIRNAME}"'/../pipeline/cleanup_catalogs.sh"
        cleanup_catalogs "$1"
    ' _ "$MARKER"
}

@test "cleanup deletes catalogs from catalogs_created" {
    marker_init "$MARKER" "run-1"
    marker_record_engine "$MARKER" "eng-1"
    marker_record_catalog_created "$MARKER" "iceberg_data"
    marker_record_catalog_created "$MARKER" "hudi_data"

    run run_cleanup_with_mock
    [ "$status" -eq 0 ]

    # Two disassociate + two delete calls expected
    grep -q "DELETE .*/spark_engines/eng-1/catalogs/iceberg_data" "$CALLS_LOG"
    grep -q "DELETE .*/spark_engines/eng-1/catalogs/hudi_data" "$CALLS_LOG"
    grep -q "DELETE .*/catalogs/iceberg_data" "$CALLS_LOG"
    grep -q "DELETE .*/catalogs/hudi_data" "$CALLS_LOG"
}

@test "cleanup does not delete catalogs in catalogs_reused" {
    marker_init "$MARKER" "run-1"
    marker_record_engine "$MARKER" "eng-1"
    marker_record_catalog_reused "$MARKER" "shared_iceberg"

    run run_cleanup_with_mock
    [ "$status" -eq 0 ]

    if [[ -f "$CALLS_LOG" ]]; then
        run grep -c "shared_iceberg" "$CALLS_LOG"
        [ "$output" = "0" ]
    fi
}

@test "cleanup with empty catalogs_created is a no-op success" {
    marker_init "$MARKER" "run-1"
    marker_record_engine "$MARKER" "eng-1"

    run run_cleanup_with_mock
    [ "$status" -eq 0 ]
}

@test "cleanup fails when marker file does not exist" {
    run run_cleanup_with_mock
    [ "$status" -ne 0 ]
    [[ "$output" == *"marker"* ]]
}

@test "_pipeline_curl invokes curl with -f/--show-error so HTTP 4xx/5xx trip the fallback" {
    run bash -c '
        # shellcheck disable=SC1091
        source "'"${BATS_TEST_DIRNAME}"'/../pipeline/cleanup_catalogs.sh"
        declare -f _pipeline_curl
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *" -f "* ]]
    [[ "$output" == *"--show-error"* ]]
}
