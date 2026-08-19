// Multi-Catalog Integration Tests (AuthZ & Non-AuthZ) for dbt-watsonx-spark.
// Design doc: docs/superpowers/specs/2026-08-13-jenkins-dbt-watsonx-pipeline-design.md
// Implementation plan: docs/superpowers/plans/2026-08-13-jenkins-dbt-watsonx-pipeline.md

pipeline {
    agent { label 'extension' }

    parameters {
        choice(name: 'DEPLOYMENT_FORM', choices: ['CPD', 'SAAS'], description: 'Target deployment platform')
        booleanParam(name: 'ENABLE_AUTHZ', defaultValue: true, description: 'Run with AuthZ enabled')
        booleanParam(name: 'SKIP_INFRA', defaultValue: false, description: 'True: skip catalog+engine creation, assume they exist (uses run_test.sh). False: full stack (uses run_catalog_tests.sh).')
        // Connection parameters — entered at build time
        string(name: 'WATSONX_HOSTNAME',    defaultValue: '', description: 'watsonx.data hostname or CPD base URL (e.g. https://cpd.example.com).')
        string(name: 'CPD_USERNAME',        defaultValue: '', description: 'CPD login username (e.g. cpadmin). Leave blank for SaaS.')
        string(name: 'CPD_PASSWORD',        defaultValue: '', description: 'CPD login password. The pipeline exchanges this for a bearer token before calling the given scripts.')
        string(name: 'WATSONX_INSTANCE_ID', defaultValue: '', description: 'watsonx.data instance ID.')
        // Catalog parameters
        string(name: 'ICEBERG_CATALOG_NAME', defaultValue: 'iceberg_data', description: 'Iceberg catalog name. Required in v1 (only catalog with test coverage).')
        string(name: 'HUDI_CATALOG_NAME',    defaultValue: 'hudi_data',    description: 'Hudi catalog name. Empty to skip Hudi.')
        string(name: 'DELTA_CATALOG_NAME',   defaultValue: 'delta_data',   description: 'Delta catalog name. Empty to skip Delta.')
        string(name: 'HIVE_CATALOG_NAME',    defaultValue: '',             description: 'Reserved for future. Ignored in v1.')
        booleanParam(name: 'DELETE_CATALOG_AFTER_TEST', defaultValue: true, description: 'Delete/drop dynamic test catalogs post-execution')
        // S3/COS storage credentials — the only values that cannot be auto-discovered from the cluster.
        // Bucket names and region are derived automatically from catalog names.
        string(name: 'STORAGE_ENDPOINT',   defaultValue: '', description: 'S3-compatible storage endpoint URL (e.g. https://s3.us-south.cloud-object-storage.appdomain.cloud).')
        string(name: 'STORAGE_ACCESS_KEY', defaultValue: '', description: 'S3 HMAC access key.')
        string(name: 'STORAGE_SECRET_KEY', defaultValue: '', description: 'S3 HMAC secret key.')
        string(name: 'LAKEHOUSE_CONSOLE_VERSION', defaultValue: '2.2.x', description: 'Target watsonx.data Console version')
        string(name: 'DBT_ADAPTER_BRANCH',   defaultValue: 'main', description: 'Target branch/tag of dbt-watsonx-data')
        string(name: 'ADAPTER_REPO_URL',     defaultValue: 'https://github.com/roneymathew/dbt-watsonx-spark.git', description: '')
        string(name: 'TIMEOUT_MINUTES',      defaultValue: '90', description: 'Overall build timeout')
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    stages {
        stage('Validate params') {
            steps {
                script {
                    if (!params.ICEBERG_CATALOG_NAME?.trim()) {
                        error 'ICEBERG_CATALOG_NAME is required in v1 (Iceberg is the only catalog with test coverage; HUDI/DELTA may be empty to skip).'
                    }
                    if (!(params.DEPLOYMENT_FORM in ['CPD', 'SAAS'])) {
                        error "DEPLOYMENT_FORM must be CPD or SAAS, got: ${params.DEPLOYMENT_FORM}"
                    }
                    if (params.SKIP_INFRA && params.DEPLOYMENT_FORM == 'SAAS') {
                        error 'SKIP_INFRA=true is not supported with DEPLOYMENT_FORM=SAAS (run_test.sh is CPD-only).'
                    }
                    if (!params.WATSONX_HOSTNAME?.trim()) {
                        error 'WATSONX_HOSTNAME is required.'
                    }
                    if (!params.CPD_USERNAME?.trim()) {
                        error 'CPD_USERNAME is required.'
                    }
                    if (!params.CPD_PASSWORD?.trim()) {
                        error 'CPD_PASSWORD is required.'
                    }
                    if (!params.WATSONX_INSTANCE_ID?.trim()) {
                        error 'WATSONX_INSTANCE_ID is required.'
                    }
                    echo "Params validated: deployment=${params.DEPLOYMENT_FORM}, authz=${params.ENABLE_AUTHZ}, skip_infra=${params.SKIP_INFRA}"
                }
            }
        }
        stage('Checkout adapter') {
            steps {
                withEnv(["BRANCH=${params.DBT_ADAPTER_BRANCH}", "REPO=${params.ADAPTER_REPO_URL}"]) {
                    sh '''
                        set -euo pipefail
                        rm -rf "${WORKSPACE}/adapter"
                        git clone --depth 1 --branch "$BRANCH" "$REPO" "${WORKSPACE}/adapter"
                        (cd "${WORKSPACE}/adapter" && git log -1 --oneline)
                    '''
                }
            }
        }
        stage('Prepare workspace') {
            steps {
                script {
                    // BUILD_TAG_SHORT: strip 'jenkins-' prefix, keep it URL-safe
                    def shortTag = env.BUILD_TAG.replaceAll('[^A-Za-z0-9-]', '-').take(32)
                    def authzMode = params.ENABLE_AUTHZ ? 'authz' : 'std'
                    env.SPARK_ENGINE_NAME = "spark-dbt-${shortTag}-${params.DEPLOYMENT_FORM.toLowerCase()}-${authzMode}"
                    env.DEPLOYMENT_TYPE = params.DEPLOYMENT_FORM.toLowerCase()
                    env.PYTHON_VENV_PATH = "${env.WORKSPACE}/.venv"
                }
                sh '''
                    set -euo pipefail
                    export HOME="${WORKSPACE}/.home"
                    mkdir -p "$HOME/.dbt"

                    python3 -m venv "${WORKSPACE}/.venv"
                    # shellcheck disable=SC1091
                    source "${WORKSPACE}/.venv/bin/activate"
                    pip install --upgrade pip
                    pip install -e "${WORKSPACE}/adapter"
                    pip install pytest dbt-tests-adapter
                '''
            }
        }
        stage('Write .env') {
            steps {
                withEnv([
                    "WATSONX_HOSTNAME=${params.WATSONX_HOSTNAME}",
                    "WATSONX_INSTANCE_ID=${params.WATSONX_INSTANCE_ID}",
                    "CPD_USERNAME=${params.CPD_USERNAME}",
                    "CPD_PASSWORD=${params.CPD_PASSWORD}",
                    "ICEBERG_CATALOG_NAME=${params.ICEBERG_CATALOG_NAME}",
                    "HUDI_CATALOG_NAME=${params.HUDI_CATALOG_NAME}",
                    "DELTA_CATALOG_NAME=${params.DELTA_CATALOG_NAME}",
                    "STORAGE_ENDPOINT=${params.STORAGE_ENDPOINT}",
                    "STORAGE_ACCESS_KEY=${params.STORAGE_ACCESS_KEY}",
                    "STORAGE_SECRET_KEY=${params.STORAGE_SECRET_KEY}"
                ]) {
                    sh '''
                        set -euo pipefail
                        set +x
                        export HOME="${WORKSPACE}/.home"

                        # Exchange username+password for a CPD bearer token.
                        # Both given scripts check: if [ -n "$AUTH_TOKEN" ]; skip own auth.
                        # Using "password" field (not "api_key") for password-based login.
                        AUTH_URL="${WATSONX_HOSTNAME}/icp4d-api/v1/authorize"
                        echo "[auth] POST ${AUTH_URL} (username=${CPD_USERNAME})"

                        # Build JSON body without backslash escaping to avoid shell quoting issues.
                        AUTH_BODY=$(printf '{"username":"%s","password":"%s"}' "${CPD_USERNAME}" "${CPD_PASSWORD}")

                        HTTP_STATUS=$(curl -s -k -o /tmp/_auth_resp.json -w "%{http_code}" \
                            -X POST "${AUTH_URL}" \
                            -H "Content-Type: application/json" \
                            -d "${AUTH_BODY}")

                        echo "[auth] HTTP status: ${HTTP_STATUS}"
                        # Print response but mask any token value for log safety
                        sed 's/"token":"[^"]*"/"token":"<REDACTED>"/g' /tmp/_auth_resp.json || true

                        AUTH_TOKEN=$(jq -r '.token // empty' /tmp/_auth_resp.json)
                        rm -f /tmp/_auth_resp.json

                        if [ -z "$AUTH_TOKEN" ]; then
                            echo "[auth] ERROR: CPD authentication failed (HTTP ${HTTP_STATUS}). Check WATSONX_HOSTNAME, CPD_USERNAME, CPD_PASSWORD." >&2
                            exit 1
                        fi
                        echo "[auth] CPD token obtained successfully (HTTP ${HTTP_STATUS})."
                        export AUTH_TOKEN

                        # WATSONX_APIKEY is expected by write_env.sh and the given scripts
                        # for Spark conf (ZenApiKey). Use the password as the key value —
                        # this is the same pattern the scripts use when building ZenApiKey.
                        export WATSONX_APIKEY="${CPD_PASSWORD}"

                        # Pre-resolve the Spark engine volume ID from the CPD spark_instances API.
                        # The given script's built-in lookup (get_available_volume_id) mixes log
                        # output with its return value, corrupting the volume_id captured by the
                        # caller. We do it cleanly here and inject it directly into .env so the
                        # script finds SPARK_ENGINE_VOLUME_ID set and skips its own lookup.
                        VOLUME_API="${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/cpd/spark_instances"
                        echo "[volume] Looking up spark-engine-volume via ${VOLUME_API}"
                        SPARK_ENGINE_VOLUME_ID=$(curl -s -k -X GET "${VOLUME_API}" \
                            -H "Authorization: Bearer ${AUTH_TOKEN}" \
                            -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \
                            | jq -r '.volumes[]? | select(.display_name == "cpd-instance::spark-engine-volume") | .instance_id // empty' \
                            | head -n1)
                        if [ -n "$SPARK_ENGINE_VOLUME_ID" ]; then
                            echo "[volume] Found volume ID: ${SPARK_ENGINE_VOLUME_ID}"
                        else
                            echo "[volume] WARNING: spark-engine-volume not found; engine will be created with a new volume"
                        fi
                        export SPARK_ENGINE_VOLUME_ID

                        bash "${WORKSPACE}/pipeline/write_env.sh" "${WORKSPACE}/adapter/.env"

                        # Append AUTH_TOKEN so the given scripts source it and skip their
                        # own auth (which uses "api_key" and would fail with a plain password).
                        echo "AUTH_TOKEN=${AUTH_TOKEN}" >> "${WORKSPACE}/adapter/.env"
                        # Only append SPARK_ENGINE_VOLUME_ID when non-empty — an empty value
                        # in .env causes the given script to run its own broken lookup (which
                        # pollutes stdout with log lines, corrupting the captured volume_id).
                        # When omitted, the script falls through to the "create new volume"
                        # branch which uses SPARK_ENGINE_VOLUME_NAME instead.
                        if [ -n "$SPARK_ENGINE_VOLUME_ID" ]; then
                            echo "SPARK_ENGINE_VOLUME_ID=${SPARK_ENGINE_VOLUME_ID}" >> "${WORKSPACE}/adapter/.env"
                        fi

                        echo "[write_env] .env key values:"
                        grep -E '^(DEPLOYMENT_TYPE|SPARK_ENGINE_NAME|SPARK_ENGINE_VOLUME_ID|STORAGE_ENDPOINT|ICEBERG_BUCKET|DELTA_BUCKET|HUDI_BUCKET)=' \
                            "${WORKSPACE}/adapter/.env" || true
                    '''
                }
            }
        }
        stage('Run given script (infra + Iceberg pytest)') {
            steps {
                withEnv([
                    "WATSONX_HOSTNAME=${params.WATSONX_HOSTNAME}",
                    "WATSONX_INSTANCE_ID=${params.WATSONX_INSTANCE_ID}",
                    "CPD_USERNAME=${params.CPD_USERNAME}",
                    "CPD_PASSWORD=${params.CPD_PASSWORD}",
                    "SKIP_INFRA=${params.SKIP_INFRA}",
                    "ENABLE_AUTHZ=${params.ENABLE_AUTHZ}",
                    "ICEBERG_CATALOG_NAME=${params.ICEBERG_CATALOG_NAME}",
                    "HUDI_CATALOG_NAME=${params.HUDI_CATALOG_NAME}",
                    "DELTA_CATALOG_NAME=${params.DELTA_CATALOG_NAME}"
                ]) {
                    sh '''
                        set -euo pipefail
                        set +x
                        export HOME="${WORKSPACE}/.home"
                        # Deploy the given scripts into the adapter checkout so their SCRIPT_DIR/..
                        # resolves to the adapter root (where tests/ lives).
                        mkdir -p "${WORKSPACE}/adapter/scripts"
                        cp -f "${WORKSPACE}/scripts/run_test.sh" "${WORKSPACE}/adapter/scripts/run_test.sh"
                        cp -f "${WORKSPACE}/scripts/run_catalog_tests.sh" "${WORKSPACE}/adapter/scripts/run_catalog_tests.sh"
                        chmod +x "${WORKSPACE}/adapter/scripts/"*.sh

                        # Re-read the token written by Write .env (avoids re-authing).
                        AUTH_TOKEN=$(grep '^AUTH_TOKEN=' "${WORKSPACE}/adapter/.env" | cut -d= -f2-)
                        export AUTH_TOKEN
                        # WATSONX_APIKEY used by Spark ZenApiKey conf inside the given scripts.
                        export WATSONX_APIKEY="${CPD_PASSWORD}"

                        # Initialize marker
                        # shellcheck disable=SC1091
                        source "${WORKSPACE}/pipeline/marker_utils.sh"
                        marker_init "${WORKSPACE}/.pipeline-marker.json" "${BUILD_TAG}"

                        # Activate venv and cd to adapter root
                        # shellcheck disable=SC1091
                        source "${WORKSPACE}/.venv/bin/activate"
                        cd "${WORKSPACE}/adapter"

                        if [ "$SKIP_INFRA" = "true" ]; then
                            SCRIPT="./scripts/run_test.sh"
                        else
                            SCRIPT="./scripts/run_catalog_tests.sh"
                        fi

                        # The given scripts' pytest invocations can't be modified directly;
                        # PYTEST_ADDOPTS lets pytest pick up --junitxml so the Report stage's
                        # junit publisher has something to find.
                        export PYTEST_ADDOPTS="--junitxml=junit-iceberg.xml"

                        # Override get_available_volume_id in the given script's subshell.
                        # The real implementation mixes log_info/log_warning output (which go
                        # to stdout) with its return value, so the caller captures garbage.
                        # Our override reads the same API cleanly — only the numeric ID goes
                        # to stdout; all log lines go to stderr.
                        # Re-read SPARK_ENGINE_VOLUME_ID from .env (may have been set by Write .env).
                        SPARK_ENGINE_VOLUME_ID=$(grep '^SPARK_ENGINE_VOLUME_ID=' "${WORKSPACE}/adapter/.env" 2>/dev/null | cut -d= -f2- || true)
                        get_available_volume_id() {
                            local vname="${1:-spark-engine-volume}"
                            # If pipeline already resolved it, return immediately.
                            if [ -n "${SPARK_ENGINE_VOLUME_ID:-}" ]; then
                                echo "$SPARK_ENGINE_VOLUME_ID"
                                return 0
                            fi
                            local base_url resp vol_id
                            base_url="${WATSONX_HOSTNAME}"
                            resp=$(curl -s -k -X GET \
                                "${base_url}/lakehouse/api/${LAKEHOUSE_API_VERSION:-v3}/${WATSONX_INSTANCE_ID}/cpd/spark_instances" \
                                -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" 2>/dev/null)
                            vol_id=$(echo "$resp" | jq -r \
                                ".volumes[]? | select(.display_name == \"cpd-instance::${vname}\") | .instance_id // empty" \
                                2>/dev/null | head -n1)
                            if [ -n "$vol_id" ]; then
                                echo "[volume-shim] found $vname → $vol_id" >&2
                                echo "$vol_id"
                                return 0
                            else
                                echo "[volume-shim] $vname not found; will create new volume" >&2
                                return 1
                            fi
                        }
                        export -f get_available_volume_id

                        "$SCRIPT"

                        # --- record what this run created, for the post/always teardown ---
                        # Re-use the already-obtained token (still valid within the run).
                        AUTH_TOKEN=$(grep '^AUTH_TOKEN=' "${WORKSPACE}/adapter/.env" | cut -d= -f2-)

                        ENGINE_ID=$(curl -s -k -X GET \
                            "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines" \
                            -H "Authorization: Bearer ${AUTH_TOKEN}" \
                            -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \
                            | jq -r ".spark_engines[]? | select(.display_name==\"${SPARK_ENGINE_NAME}\") | .id // .engine_id" \
                            | head -n1)
                        if [ -n "$ENGINE_ID" ]; then
                            marker_record_engine "${WORKSPACE}/.pipeline-marker.json" "$ENGINE_ID"
                        else
                            echo "[marker] warn: could not resolve engine id for ${SPARK_ENGINE_NAME}; teardown will not delete the engine" >&2
                        fi

                        # SKIP_INFRA=true means run_test.sh assumes the catalogs already
                        # exist (it does not create them) — mark them reused so cleanup
                        # never deletes catalogs this run didn't create.
                        record_catalog() {
                            local catalog_name=$1
                            [ -z "$catalog_name" ] && return 0
                            if [ "$SKIP_INFRA" = "true" ]; then
                                marker_record_catalog_reused "${WORKSPACE}/.pipeline-marker.json" "$catalog_name"
                            else
                                marker_record_catalog_created "${WORKSPACE}/.pipeline-marker.json" "$catalog_name"
                            fi
                        }
                        record_catalog "$ICEBERG_CATALOG_NAME"
                        record_catalog "$HUDI_CATALOG_NAME"
                        record_catalog "$DELTA_CATALOG_NAME"
                    '''
                }
            }
        }
        stage('Per-catalog pytest sweep (Hudi/Delta)') {
            steps {
                withEnv([
                    "WATSONX_HOSTNAME=${params.WATSONX_HOSTNAME}",
                    "WATSONX_INSTANCE_ID=${params.WATSONX_INSTANCE_ID}",
                    "CPD_USERNAME=${params.CPD_USERNAME}",
                    "CPD_PASSWORD=${params.CPD_PASSWORD}"
                ]) {
                script {
                    // === 3-part naming workaround ===
                    // Only Iceberg supports catalog.schema.table naming today.
                    // Hive/Hudi/Delta must use the literal 'spark_catalog' as the
                    // session catalog. Delete this block when the platform ships
                    // full 3-part support (~est. Nov 2026 per teammate).
                    def CATALOGS_REQUIRING_SPARK_CATALOG_ALIAS = ['hudi', 'delta', 'hive'] as Set
                    def effectiveCatalog = { String catalogType, String userSuppliedName ->
                        if (CATALOGS_REQUIRING_SPARK_CATALOG_ALIAS.contains(catalogType.toLowerCase())) {
                            return 'spark_catalog'
                        }
                        return userSuppliedName
                    }
                    // === /workaround ===

                    def profileName = params.ENABLE_AUTHZ ? 'watsonx_authz_test' : 'watsonx_test'
                    def qsName = params.ENABLE_AUTHZ ? 'dbt-authz-qs' : 'dbt-standard-qs'

                    def rounds = [
                        [type: 'hudi',  name: params.HUDI_CATALOG_NAME],
                        [type: 'delta', name: params.DELTA_CATALOG_NAME],
                    ].findAll { it.name?.trim() }

                    if (rounds.isEmpty()) {
                        echo 'No Hudi/Delta catalogs requested; skipping sweep.'
                        return
                    }

                    for (round in rounds) {
                        def catalogType = round.type
                        def catalogName = round.name
                        def effective = effectiveCatalog(catalogType, catalogName)
                        catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
                            withEnv([
                                "QS_NAME=${qsName}",
                                "CATALOG_TYPE=${catalogType}",
                                "CATALOG_NAME=${catalogName}",
                                "EFFECTIVE_CATALOG=${effective}",
                                "PROFILE_NAME=${profileName}"
                            ]) {
                                sh '''
                                    set -euo pipefail
                                    set +x
                                    export HOME="${WORKSPACE}/.home"
                                    # shellcheck disable=SC1091
                                    source "${WORKSPACE}/.venv/bin/activate"

                                    AUTH_BODY=$(printf '{"username":"%s","password":"%s"}' "${CPD_USERNAME}" "${CPD_PASSWORD}")
                                    AUTH_TOKEN=$(curl -s -k -X POST \
                                        "${WATSONX_HOSTNAME}/icp4d-api/v1/authorize" \
                                        -H "Content-Type: application/json" \
                                        -d "${AUTH_BODY}" \
                                        | jq -r '.token // empty')

                                    ENGINE_ID=$(curl -s -k -X GET \
                                        "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines" \
                                        -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                        -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \
                                        | jq -r ".spark_engines[]? | select(.display_name==\"${SPARK_ENGINE_NAME}\") | .id // .engine_id" \
                                        | head -n1)

                                    QS_ID=$(curl -s -k -X GET \
                                        "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines/${ENGINE_ID}/query_servers" \
                                        -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                        -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \
                                        | jq -r ".query_servers[]? | select(.query_server_details.name==\"${QS_NAME}\") | .id" \
                                        | head -n1)

                                    export WATSONX_URI="/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines/${ENGINE_ID}/query_servers/${QS_ID}/connect/cliservice"
                                    export WATSONX_CATALOG="${EFFECTIVE_CATALOG}"
                                    export WATSONX_SCHEMA="wxd_schema"
                                    export WATSONX_HOST="${WATSONX_HOSTNAME}"
                                    export WATSONX_INSTANCE="${WATSONX_INSTANCE_ID}"
                                    export WATSONX_USER="${CPD_USERNAME}"
                                    export ADAPTER_ROOT="${WORKSPACE}/adapter"
                                    export PYTEST_TEST_PATTERN="tests/functional/adapter/catalog_tests/"

                                    echo "[sweep] catalog_type=${CATALOG_TYPE} catalog_name=${CATALOG_NAME} effective=${WATSONX_CATALOG}"
                                    bash "${WORKSPACE}/pipeline/run_pytest_for_catalog.sh"
                                '''
                            }
                        }
                    }
                }
                } // withEnv
            }
        }
        stage('Report') {
            steps {
                sh '''
                    set -euo pipefail
                    echo "=== Build summary ==="
                    echo "deployment=${DEPLOYMENT_TYPE} authz=''' + "${params.ENABLE_AUTHZ}" + '''"
                    echo "engine=${SPARK_ENGINE_NAME}"
                    if [ -f "${WORKSPACE}/.pipeline-marker.json" ]; then
                        cat "${WORKSPACE}/.pipeline-marker.json"
                    fi
                '''
                junit allowEmptyResults: true, testResults: 'adapter/**/junit-*.xml'
            }
        }
    }

    post {
        always {
            node('extension') {
                withEnv([
                    "WATSONX_HOSTNAME=${params.WATSONX_HOSTNAME}",
                    "WATSONX_INSTANCE_ID=${params.WATSONX_INSTANCE_ID}",
                    "CPD_USERNAME=${params.CPD_USERNAME}",
                    "CPD_PASSWORD=${params.CPD_PASSWORD}",
                    "DELETE_CATALOG_AFTER_TEST=${params.DELETE_CATALOG_AFTER_TEST}"
                ]) {
                    sh '''
                        set +e
                        set +x
                        export HOME="${WORKSPACE}/.home"

                        if [ -f "${WORKSPACE}/.pipeline-marker.json" ]; then
                            AUTH_BODY=$(printf '{"username":"%s","password":"%s"}' "${CPD_USERNAME}" "${CPD_PASSWORD}")
                            AUTH_TOKEN=$(curl -s -k -X POST \
                                "${WATSONX_HOSTNAME}/icp4d-api/v1/authorize" \
                                -H "Content-Type: application/json" \
                                -d "${AUTH_BODY}" \
                                | jq -r '.token // empty')
                            export AUTH_TOKEN
                            export LAKEHOUSE_API_VERSION="v3"

                            if [ "$DELETE_CATALOG_AFTER_TEST" = "true" ]; then
                                echo "[teardown] DELETE_CATALOG_AFTER_TEST=true; running cleanup_catalogs.sh"
                                bash "${WORKSPACE}/pipeline/cleanup_catalogs.sh" "${WORKSPACE}/.pipeline-marker.json" || true
                            else
                                echo "[teardown] DELETE_CATALOG_AFTER_TEST=false; leaving catalogs in place"
                            fi

                            # Delete this build's Spark engine unconditionally (unique-named per build).
                            # shellcheck disable=SC1091
                            source "${WORKSPACE}/pipeline/marker_utils.sh"
                            ENGINE_ID=$(marker_get_engine_id "${WORKSPACE}/.pipeline-marker.json")
                            if [ -n "$ENGINE_ID" ]; then
                                echo "[teardown] deleting Spark engine $ENGINE_ID"
                                curl -s -k -X DELETE \
                                    "${WATSONX_HOSTNAME}/lakehouse/api/${LAKEHOUSE_API_VERSION}/${WATSONX_INSTANCE_ID}/spark_engines/${ENGINE_ID}" \
                                    -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                    -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" || true
                            fi
                        else
                            echo "[teardown] no marker file; nothing to clean up"
                        fi

                        # Workspace purge
                        rm -rf "${WORKSPACE}/.venv" "${WORKSPACE}/.home" \
                               "${WORKSPACE}/adapter/.env" "${WORKSPACE}/.env" \
                               "${WORKSPACE}/adapter" "${WORKSPACE}/.pipeline-marker.json"
                    '''
                }
            } // node
        }
    }
}
