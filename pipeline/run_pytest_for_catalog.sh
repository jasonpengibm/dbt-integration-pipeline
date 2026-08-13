#!/usr/bin/env bash
# run_pytest_for_catalog.sh — invoke pytest against the adapter with the caller-supplied
# WATSONX_CATALOG in effect. The 3-part naming aliasing decision has already been made
# by the Jenkinsfile; this script only forwards.
set -euo pipefail

require() {
    local var=$1
    if [[ -z "${!var:-}" ]]; then
        echo "error: required env var $var is not set" >&2
        exit 1
    fi
}

require WATSONX_CATALOG
require WATSONX_URI
require WATSONX_HOST
require WATSONX_APIKEY
require WATSONX_INSTANCE
require PROFILE_NAME
require ADAPTER_ROOT

WATSONX_SCHEMA="${WATSONX_SCHEMA:-wxd_schema}"
WATSONX_USER="${WATSONX_USER:-admin}"
PYTEST_TEST_PATTERN="${PYTEST_TEST_PATTERN:-tests/functional/adapter/}"

export WATSONX_CATALOG WATSONX_SCHEMA WATSONX_URI WATSONX_HOST
export WATSONX_APIKEY WATSONX_INSTANCE WATSONX_USER

cd "$ADAPTER_ROOT"

echo "[pytest] catalog=$WATSONX_CATALOG profile=$PROFILE_NAME pattern=$PYTEST_TEST_PATTERN"
exec pytest "$PYTEST_TEST_PATTERN" -v --profile "$PROFILE_NAME" --tb=short
