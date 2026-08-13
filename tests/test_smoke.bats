#!/usr/bin/env bats

load 'test_helpers'

setup() {
    setup_pipeline_test_env
}

teardown() {
    teardown_pipeline_test_env
}

@test "bats can execute a passing test" {
    run bash -c 'echo hello'
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "TEST_TMPDIR is created and isolated" {
    [ -d "$TEST_TMPDIR" ]
    [ "$HOME" = "$TEST_TMPDIR/home" ]
}
