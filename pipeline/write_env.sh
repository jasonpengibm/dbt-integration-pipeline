#!/usr/bin/env bash
# write_env.sh — render a .env file for the given-scripts to source.
# Usage: bash write_env.sh <output_path>
set -euo pipefail

OUTPUT_PATH="${1:-}"
if [[ -z "$OUTPUT_PATH" ]]; then
    echo "usage: write_env.sh <output_path>" >&2
    exit 2
fi

# Required unconditionally
REQUIRED_ALWAYS=(
    DEPLOYMENT_TYPE
    WATSONX_HOSTNAME
    WATSONX_APIKEY
    WATSONX_INSTANCE_ID
    SPARK_ENGINE_NAME
    PYTHON_VENV_PATH
)

for var in "${REQUIRED_ALWAYS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "error: required env var $var is not set" >&2
        exit 1
    fi
done

# CPD-only
if [[ "$DEPLOYMENT_TYPE" == "cpd" && -z "${CPD_USERNAME:-}" ]]; then
    echo "error: CPD_USERNAME is required when DEPLOYMENT_TYPE=cpd" >&2
    exit 1
fi

catalog_enabled() {
    local name=${1:-}
    if [[ -z "$name" ]]; then echo "false"; else echo "true"; fi
}

LAKEHOUSE_API_VERSION="${LAKEHOUSE_API_VERSION:-v3}"

umask 077
{
    echo "DEPLOYMENT_TYPE=$DEPLOYMENT_TYPE"
    echo "WATSONX_HOSTNAME=$WATSONX_HOSTNAME"
    echo "WATSONX_HOST=$WATSONX_HOSTNAME"
    echo "CPD_URL=$WATSONX_HOSTNAME"
    echo "WATSONX_APIKEY=$WATSONX_APIKEY"
    echo "WATSONX_INSTANCE_ID=$WATSONX_INSTANCE_ID"
    echo "CPD_USERNAME=${CPD_USERNAME:-}"
    echo "ICEBERG_CATALOG_NAME=${ICEBERG_CATALOG_NAME:-}"
    echo "ICEBERG_CATALOG_ENABLED=$(catalog_enabled "${ICEBERG_CATALOG_NAME:-}")"
    echo "HUDI_CATALOG_NAME=${HUDI_CATALOG_NAME:-}"
    echo "HUDI_CATALOG_ENABLED=$(catalog_enabled "${HUDI_CATALOG_NAME:-}")"
    echo "DELTA_CATALOG_NAME=${DELTA_CATALOG_NAME:-}"
    echo "DELTA_CATALOG_ENABLED=$(catalog_enabled "${DELTA_CATALOG_NAME:-}")"
    echo "SPARK_ENGINE_NAME=$SPARK_ENGINE_NAME"
    echo "SPARK_ENGINE_AUTHZ_NAME=${SPARK_ENGINE_NAME}-authz"
    echo "PYTHON_VENV_PATH=$PYTHON_VENV_PATH"
    echo "LAKEHOUSE_API_VERSION=$LAKEHOUSE_API_VERSION"
    # S3/COS storage credentials (passed from pipeline params — cannot be auto-discovered)
    echo "STORAGE_ENDPOINT=${STORAGE_ENDPOINT:-}"
    echo "STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY:-}"
    echo "STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY:-}"
    echo "STORAGE_REGION=us-south"
    # Bucket names: use *_BUCKET_OVERRIDE if the pipeline supplied one, otherwise
    # derive from catalog name: <catalog_name>-bucket (hyphens replace underscores).
    echo "ICEBERG_BUCKET=${ICEBERG_BUCKET_OVERRIDE:-$(echo "${ICEBERG_CATALOG_NAME:-iceberg_data}" | tr '_' '-')-bucket}"
    echo "DELTA_BUCKET=${DELTA_BUCKET_OVERRIDE:-$(echo "${DELTA_CATALOG_NAME:-delta_data}" | tr '_' '-')-bucket}"
    echo "HUDI_BUCKET=${HUDI_BUCKET_OVERRIDE:-$(echo "${HUDI_CATALOG_NAME:-hudi_data}" | tr '_' '-')-bucket}"
    # Volume name for Spark engine home (volume ID is resolved and appended by the pipeline after this script)
    echo "SPARK_ENGINE_VOLUME_NAME=spark-engine-volume"
} > "$OUTPUT_PATH"

chmod 600 "$OUTPUT_PATH"
