#!/usr/bin/env bats

load 'test_helpers'

setup() {
    setup_pipeline_test_env
    WRITE_ENV="${BATS_TEST_DIRNAME}/../pipeline/write_env.sh"
    OUTPUT="$TEST_TMPDIR/.env"
    # Baseline required vars
    export DEPLOYMENT_TYPE=cpd
    export WATSONX_HOSTNAME=https://cpd.example.com
    export WATSONX_APIKEY=secret
    export WATSONX_INSTANCE_ID=inst-1
    export CPD_USERNAME=admin
    export SPARK_ENGINE_NAME=spark-test
    export PYTHON_VENV_PATH=/tmp/venv
    export ICEBERG_CATALOG_NAME=iceberg_data
    export HUDI_CATALOG_NAME=hudi_data
    export DELTA_CATALOG_NAME=delta_data
}

teardown() {
    teardown_pipeline_test_env
}

@test "write_env creates the .env file with mode 600" {
    run bash "$WRITE_ENV" "$OUTPUT"
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT" ]
    local mode
    mode=$(stat -f '%A' "$OUTPUT" 2>/dev/null || stat -c '%a' "$OUTPUT")
    [ "$mode" = "600" ]
}

@test "write_env sets DEPLOYMENT_TYPE from env" {
    run bash "$WRITE_ENV" "$OUTPUT"
    grep -q '^DEPLOYMENT_TYPE=cpd$' "$OUTPUT"
}

@test "write_env sets three hostname aliases to the same value" {
    run bash "$WRITE_ENV" "$OUTPUT"
    grep -q '^WATSONX_HOSTNAME=https://cpd.example.com$' "$OUTPUT"
    grep -q '^WATSONX_HOST=https://cpd.example.com$' "$OUTPUT"
    grep -q '^CPD_URL=https://cpd.example.com$' "$OUTPUT"
}

@test "write_env sets ICEBERG_CATALOG_ENABLED=true when name is non-empty" {
    run bash "$WRITE_ENV" "$OUTPUT"
    grep -q '^ICEBERG_CATALOG_ENABLED=true$' "$OUTPUT"
}

@test "write_env sets ICEBERG_CATALOG_ENABLED=false when name is empty" {
    export ICEBERG_CATALOG_NAME=""
    run bash "$WRITE_ENV" "$OUTPUT"
    grep -q '^ICEBERG_CATALOG_ENABLED=false$' "$OUTPUT"
}

@test "write_env derives SPARK_ENGINE_AUTHZ_NAME from SPARK_ENGINE_NAME" {
    run bash "$WRITE_ENV" "$OUTPUT"
    grep -q '^SPARK_ENGINE_NAME=spark-test$' "$OUTPUT"
    grep -q '^SPARK_ENGINE_AUTHZ_NAME=spark-test-authz$' "$OUTPUT"
}

@test "write_env fails with clear error when required var is missing" {
    unset WATSONX_APIKEY
    run bash "$WRITE_ENV" "$OUTPUT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"WATSONX_APIKEY"* ]]
}

@test "write_env accepts CPD_USERNAME unset when DEPLOYMENT_TYPE=saas" {
    export DEPLOYMENT_TYPE=saas
    unset CPD_USERNAME
    run bash "$WRITE_ENV" "$OUTPUT"
    [ "$status" -eq 0 ]
}

@test "write_env defaults LAKEHOUSE_API_VERSION to v3 when unset" {
    unset LAKEHOUSE_API_VERSION
    run bash "$WRITE_ENV" "$OUTPUT"
    grep -q '^LAKEHOUSE_API_VERSION=v3$' "$OUTPUT"
}
