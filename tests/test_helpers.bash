#!/usr/bin/env bash
# Shared bats helpers. Source from every .bats file's setup().

setup_pipeline_test_env() {
    TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/pipeline-XXXXXX")"
    export TEST_TMPDIR
    # By default, isolate HOME so tests can't touch the real ~/.dbt
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME"
}

teardown_pipeline_test_env() {
    if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}
