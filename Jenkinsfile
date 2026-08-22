// dbt-watsonx-spark integration test automation pipeline
//
// Flow: validate params → clone the adapter under test → build Python
// venv → authenticate to CPD and write .env → run the given script (creates
// catalogs, 2 Spark engines, a query server, then runs the Iceberg pytest suite)
// → sweep Hudi/Delta pytest → publish junit (collect test result) → teardown (always runs: delete this
// build's engines and any catalogs this build created, then purge the workspace).

pipeline {
    agent { label 'extension' }

    parameters {
        choice(name: 'DEPLOYMENT_FORM', choices: ['CPD', 'SAAS'], description: 'Target deployment platform')
        booleanParam(name: 'ENABLE_AUTHZ', defaultValue: true, description: 'Run tests against the authz-enabled engine (else the standard one).')
        booleanParam(name: 'SKIP_INFRA', defaultValue: false, description: 'True: skip catalog+engine creation, assume they exist (uses run_test.sh). False: full stack (uses run_catalog_tests.sh).')

        // CPD / watsonx.data connection
        string(name: 'WATSONX_HOSTNAME',    defaultValue: '', description: 'watsonx.data hostname or CPD base URL (e.g. https://cpd.example.com).')
        string(name: 'CPD_USERNAME',        defaultValue: '', description: 'CPD login username (e.g. cpadmin). Leave blank for SaaS.')
        string(name: 'CPD_PASSWORD',        defaultValue: '', description: 'CPD login password. The pipeline exchanges it for a bearer token before calling the given scripts.')
        string(name: 'WATSONX_INSTANCE_ID', defaultValue: '', description: 'watsonx.data instance ID.')

        // Catalogs to exercise. Blank = skip that catalog.
        string(name: 'ICEBERG_CATALOG_NAME', defaultValue: 'iceberg_data', description: 'Iceberg catalog name. Required.')
        string(name: 'HUDI_CATALOG_NAME',    defaultValue: 'hudi_data',    description: 'Hudi catalog name. Empty to skip Hudi.')
        string(name: 'DELTA_CATALOG_NAME',   defaultValue: 'delta_data',   description: 'Delta catalog name. Empty to skip Delta.')
        string(name: 'HIVE_CATALOG_NAME',    defaultValue: '',             description: 'Reserved for future. Ignored in v1.')
        booleanParam(name: 'DELETE_CATALOG_AFTER_TEST', defaultValue: true, description: 'Delete dynamic test catalogs post-execution')

        // COS storage. Cannot be auto-discovered from the cluster.
        string(name: 'STORAGE_ENDPOINT',   defaultValue: '', description: 'S3-compatible endpoint URL (e.g. https://s3.us-south.cloud-object-storage.appdomain.cloud).')
        string(name: 'STORAGE_ACCESS_KEY', defaultValue: '', description: 'S3 HMAC access key.')
        string(name: 'STORAGE_SECRET_KEY', defaultValue: '', description: 'S3 HMAC secret key.')

        // Bucket-name overrides. Blank = derive from catalog name (<catalog>-bucket, underscores→hyphens).
        string(name: 'ICEBERG_BUCKET_NAME', defaultValue: '', description: 'Iceberg bucket (default: derived from ICEBERG_CATALOG_NAME).')
        string(name: 'HUDI_BUCKET_NAME',    defaultValue: '', description: 'Hudi bucket (default: derived from HUDI_CATALOG_NAME).')
        string(name: 'DELTA_BUCKET_NAME',   defaultValue: '', description: 'Delta bucket (default: derived from DELTA_CATALOG_NAME).')

        string(name: 'LAKEHOUSE_CONSOLE_VERSION', defaultValue: '2.2.x', description: 'Target watsonx.data Console version')
        string(name: 'DBT_ADAPTER_BRANCH',   defaultValue: 'main', description: 'Branch/tag of the adapter repo to test.')
        string(name: 'ADAPTER_REPO_URL',     defaultValue: 'https://github.com/roneymathew/dbt-watsonx-spark.git', description: 'Adapter git repo.')
        string(name: 'TIMEOUT_MINUTES',      defaultValue: '90', description: 'Overall build timeout.')
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    stages {
        // Check missing or invalid inputs.
        stage('Validate params') {
            steps {
                script {
                    if (!params.ICEBERG_CATALOG_NAME?.trim()) {
                        error 'ICEBERG_CATALOG_NAME is required (HUDI/DELTA may be blank to skip).'
                    }
                    if (!(params.DEPLOYMENT_FORM in ['CPD', 'SAAS'])) {
                        error "DEPLOYMENT_FORM must be CPD or SAAS, got: ${params.DEPLOYMENT_FORM}"
                    }
                    if (params.SKIP_INFRA && params.DEPLOYMENT_FORM == 'SAAS') {
                        error 'SKIP_INFRA=true is not supported with DEPLOYMENT_FORM=SAAS (run_test.sh is CPD-only).'
                    }
                    if (!params.WATSONX_HOSTNAME?.trim())    { error 'WATSONX_HOSTNAME is required.' }
                    if (!params.CPD_USERNAME?.trim())        { error 'CPD_USERNAME is required.' }
                    if (!params.CPD_PASSWORD?.trim())        { error 'CPD_PASSWORD is required.' }
                    if (!params.WATSONX_INSTANCE_ID?.trim()) { error 'WATSONX_INSTANCE_ID is required.' }
                    echo "Params validated: deployment=${params.DEPLOYMENT_FORM}, authz=${params.ENABLE_AUTHZ}, skip_infra=${params.SKIP_INFRA}"
                }
            }
        }

        // Clone the adapter under test into ${WORKSPACE}/adapter.
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

        // Python venv + install the adapter and pytest. Torn down in post/always.
        stage('Prepare workspace') {
            steps {
                script {
                    // SPARK_ENGINE_NAME is *base*. The given run_catalog_tests.sh
                    // always creates two engines per run: <base> (standard) and
                    // <base>-authz. Do not bake -authz/-std into the base or the
                    // script's derivation produces <base>-authz-authz.
                    def shortTag = env.BUILD_TAG.replaceAll('[^A-Za-z0-9-]', '-').take(24)
                    env.SPARK_ENGINE_NAME       = "spark-dbt-${shortTag}-${params.DEPLOYMENT_FORM.toLowerCase()}"
                    env.SPARK_ENGINE_AUTHZ_NAME = "${env.SPARK_ENGINE_NAME}-authz"
                    env.DEPLOYMENT_TYPE         = params.DEPLOYMENT_FORM.toLowerCase()
                    env.PYTHON_VENV_PATH        = "${env.WORKSPACE}/.venv"
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

        // Authenticate to CPD, and render the
        // .env file the given scripts read.
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
                    "STORAGE_SECRET_KEY=${params.STORAGE_SECRET_KEY}",
                    "ICEBERG_BUCKET_OVERRIDE=${params.ICEBERG_BUCKET_NAME}",
                    "HUDI_BUCKET_OVERRIDE=${params.HUDI_BUCKET_NAME}",
                    "DELTA_BUCKET_OVERRIDE=${params.DELTA_BUCKET_NAME}"
                ]) {
                    sh '''
                        set -euo pipefail
                        set +x
                        export HOME="${WORKSPACE}/.home"

                        # 1. Exchange username+password for a CPD bearer token. The given
                        #    scripts see AUTH_TOKEN set and skip their own (broken) auth.
                        AUTH_URL="${WATSONX_HOSTNAME}/icp4d-api/v1/authorize"
                        echo "[auth] POST ${AUTH_URL} (username=${CPD_USERNAME})"
                        AUTH_BODY=$(printf '{"username":"%s","password":"%s"}' "${CPD_USERNAME}" "${CPD_PASSWORD}")
                        HTTP_STATUS=$(curl -s -k -o /tmp/_auth_resp.json -w "%{http_code}" \
                            -X POST "${AUTH_URL}" \
                            -H "Content-Type: application/json" \
                            -d "${AUTH_BODY}")
                        echo "[auth] HTTP status: ${HTTP_STATUS}"
                        sed 's/"token":"[^"]*"/"token":"<REDACTED>"/g' /tmp/_auth_resp.json || true
                        AUTH_TOKEN=$(jq -r '.token // empty' /tmp/_auth_resp.json)
                        rm -f /tmp/_auth_resp.json
                        if [ -z "$AUTH_TOKEN" ]; then
                            echo "[auth] ERROR: CPD authentication failed (HTTP ${HTTP_STATUS}). Check host/user/password." >&2
                            exit 1
                        fi
                        echo "[auth] CPD token obtained."
                        export AUTH_TOKEN

                        # The given scripts build Spark's ZenApiKey from CPD_PASSWORD.
                        export WATSONX_APIKEY="${CPD_PASSWORD}"

                        # 2. Pre-resolve the Spark engine volume ID. The given script's own
                        #    lookup writes log lines to stdout and corrupts the captured id;
                        #    doing it here cleanly lets the script skip its version.
                        #
                        #    Candidate volumes in preference order — first one found wins.
                        #    spark-engine-volume PVC is Pending (nfs-client provisioner absent).
                        #    spark-vol PVC is Bound on managed-nfs-storage and is the working one.
                        VOLUME_CANDIDATES="spark-vol spark-engine-volume"
                        VOLUME_API="${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/cpd/spark_instances"
                        echo "[volume] Querying ${VOLUME_API}"
                        VOLUME_RESPONSE=$(curl -s -k -X GET "${VOLUME_API}" \
                            -H "Authorization: Bearer ${AUTH_TOKEN}" \
                            -H "LhInstanceId: ${WATSONX_INSTANCE_ID}")
                        echo "[volume] Available volumes:"
                        echo "$VOLUME_RESPONSE" | jq -r '.volumes[]? | [.display_name, .instance_id] | join(" -> ")' 2>/dev/null || true
                        SPARK_ENGINE_VOLUME_ID=""
                        for CANDIDATE in $VOLUME_CANDIDATES; do
                            _VID=$(echo "$VOLUME_RESPONSE" \
                                | jq -r --arg n "cpd-instance::${CANDIDATE}" \
                                    '.volumes[]? | select(.display_name == $n) | .instance_id // empty' \
                                | head -n1)
                            if [ -n "$_VID" ]; then
                                SPARK_ENGINE_VOLUME_ID="$_VID"
                                echo "[volume] Using '${CANDIDATE}' -> ID: ${SPARK_ENGINE_VOLUME_ID}"
                                break
                            fi
                        done
                        if [ -z "$SPARK_ENGINE_VOLUME_ID" ]; then
                            echo "[volume] ERROR: none of the candidate volumes (${VOLUME_CANDIDATES}) were found." >&2
                            echo "[volume] Add the correct volume name (without cpd-instance:: prefix) to VOLUME_CANDIDATES." >&2
                            exit 1
                        fi
                        export SPARK_ENGINE_VOLUME_ID

                        # 3. Render .env and append the token + volume id for the given script.
                        bash "${WORKSPACE}/pipeline/write_env.sh" "${WORKSPACE}/adapter/.env"
                        echo "AUTH_TOKEN=${AUTH_TOKEN}" >> "${WORKSPACE}/adapter/.env"
                        # Only write SPARK_ENGINE_VOLUME_ID when non-empty — an empty value
                        # triggers the script's broken lookup path.
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

        // Copy given scripts, patch in the volume, mark any existing
        // catalogs as reused, then run the given script (creates catalogs + 2 engines +
        // query server, then runs the Iceberg pytest suite). Records what to clean up.
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

                        # Copy the given scripts into the adapter checkout so their
                        # SCRIPT_DIR/.. resolves to the adapter root (where tests/ lives).
                        mkdir -p "${WORKSPACE}/adapter/scripts"
                        cp -f "${WORKSPACE}/scripts/run_test.sh"          "${WORKSPACE}/adapter/scripts/run_test.sh"
                        cp -f "${WORKSPACE}/scripts/run_catalog_tests.sh" "${WORKSPACE}/adapter/scripts/run_catalog_tests.sh"
                        chmod +x "${WORKSPACE}/adapter/scripts/"*.sh

                        # Inject `source <volume_shim.sh>` right before the script's
                        # `main "$@"` call. The script defines get_available_volume_id
                        # itself (~line 756), which overrides any exported version, so
                        # the shim must be sourced AFTER that definition and BEFORE main.
                        SHIM_PATH="${WORKSPACE}/pipeline/volume_shim.sh"
                        SCRIPT_COPY="${WORKSPACE}/adapter/scripts/run_catalog_tests.sh"
                        if ! grep -q 'volume_shim.sh' "$SCRIPT_COPY"; then
                            # -v q='"' passes the double-quote as a variable so we do not
                            # have to escape it through Groovy → shell → awk.
                            awk -v shim="$SHIM_PATH" -v q='"' '
                                /^# Run main function$/ && !injected {
                                    print "# volume shim injected by pipeline"
                                    print "source " q shim q
                                    injected = 1
                                }
                                { print }
                                END {
                                    if (!injected) {
                                        print "[patch] ERROR: anchor line not found in run_catalog_tests.sh" > "/dev/stderr"
                                        exit 1
                                    }
                                }
                            ' "$SCRIPT_COPY" > "${SCRIPT_COPY}.new"
                            mv "${SCRIPT_COPY}.new" "$SCRIPT_COPY"
                            chmod +x "$SCRIPT_COPY"
                            echo "[patch] injected volume_shim.sh before main() call"
                        fi

                        # Re-use the token written to .env (no need to re-auth).
                        AUTH_TOKEN=$(grep '^AUTH_TOKEN=' "${WORKSPACE}/adapter/.env" | cut -d= -f2-)
                        export AUTH_TOKEN
                        export WATSONX_APIKEY="${CPD_PASSWORD}"

                        # shellcheck disable=SC1091
                        source "${WORKSPACE}/pipeline/marker_utils.sh"
                        MARKER="${WORKSPACE}/.pipeline-marker.json"
                        marker_init "$MARKER" "${BUILD_TAG}"

                        # Preflight: catalogs that ALREADY exist get recorded as `_reused`.
                        # cleanup_catalogs.sh only deletes catalogs in `_created`, so
                        # pre-existing (shared/baseline) catalogs stay safe on teardown.
                        preflight_catalog() {
                            local catalog_name=$1
                            [ -z "$catalog_name" ] && return 0
                            local http
                            http=$(curl -s -k -o /dev/null -w "%{http_code}" -X GET \
                                "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/catalogs/${catalog_name}" \
                                -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \
                                -H "AuthInstanceId: ${WATSONX_INSTANCE_ID}")
                            if [ "$http" = "200" ]; then
                                marker_record_catalog_reused "$MARKER" "$catalog_name"
                                echo "[preflight] '$catalog_name' already exists — will preserve on teardown"
                            else
                                echo "[preflight] '$catalog_name' not found (HTTP $http) — will treat as created-by-this-run"
                            fi
                        }
                        preflight_catalog "$ICEBERG_CATALOG_NAME"
                        preflight_catalog "$HUDI_CATALOG_NAME"
                        preflight_catalog "$DELTA_CATALOG_NAME"

                        # shellcheck disable=SC1091
                        source "${WORKSPACE}/.venv/bin/activate"
                        cd "${WORKSPACE}/adapter"

                        # SKIP_INFRA branches between "create everything then test" and
                        # "assume infra exists, just test".
                        if [ "$SKIP_INFRA" = "true" ]; then
                            SCRIPT="./scripts/run_test.sh"
                        else
                            SCRIPT="./scripts/run_catalog_tests.sh"
                        fi

                        # The given script's pytest invocation is fixed; PYTEST_ADDOPTS is
                        # the way to get a --junitxml into it for the Report stage.
                        export PYTEST_ADDOPTS="--junitxml=junit-iceberg.xml"

                        "$SCRIPT"

                        # Record engines and catalogs this run touched, for teardown.
                        AUTH_TOKEN=$(grep '^AUTH_TOKEN=' "${WORKSPACE}/adapter/.env" | cut -d= -f2-)

                        # The given script always creates BOTH <base> and <base>-authz —
                        # record both ids or the second one leaks on teardown.
                        SPARK_ENGINES_JSON=$(curl -s -k -X GET \
                            "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines" \
                            -H "Authorization: Bearer ${AUTH_TOKEN}" \
                            -H "LhInstanceId: ${WATSONX_INSTANCE_ID}")
                        for engine_display in "$SPARK_ENGINE_NAME" "$SPARK_ENGINE_AUTHZ_NAME"; do
                            EID=$(echo "$SPARK_ENGINES_JSON" \
                                | jq -r --arg n "$engine_display" \
                                    '.spark_engines[]? | select(.display_name==$n) | .id // .engine_id' \
                                | head -n1)
                            if [ -n "$EID" ]; then
                                marker_record_engine "$MARKER" "$EID"
                                echo "[marker] recorded engine ${engine_display} (id=$EID)"
                            else
                                echo "[marker] warn: engine ${engine_display} not found; teardown will not delete it" >&2
                            fi
                        done

                        # Anything preflight already marked reused stays reused. Everything
                        # else is attributed to this run (or reused when SKIP_INFRA=true,
                        # since run_test.sh does not create catalogs).
                        record_catalog() {
                            local catalog_name=$1
                            [ -z "$catalog_name" ] && return 0
                            if marker_has_catalog_reused "$MARKER" "$catalog_name"; then
                                return 0
                            fi
                            if [ "$SKIP_INFRA" = "true" ]; then
                                marker_record_catalog_reused "$MARKER" "$catalog_name"
                            else
                                marker_record_catalog_created "$MARKER" "$catalog_name"
                            fi
                        }
                        record_catalog "$ICEBERG_CATALOG_NAME"
                        record_catalog "$HUDI_CATALOG_NAME"
                        record_catalog "$DELTA_CATALOG_NAME"
                    '''
                }
            }
        }

        //  Run pytest against Hudi and Delta on the same engine
        stage('Per-catalog pytest sweep (Hudi/Delta)') {
            steps {
                withEnv([
                    "WATSONX_HOSTNAME=${params.WATSONX_HOSTNAME}",
                    "WATSONX_INSTANCE_ID=${params.WATSONX_INSTANCE_ID}",
                    "CPD_USERNAME=${params.CPD_USERNAME}",
                    "CPD_PASSWORD=${params.CPD_PASSWORD}"
                ]) {
                script {
                    // 3-part naming workaround: only Iceberg supports catalog.schema.table
                    // today. Hive/Hudi/Delta must use the literal 'spark_catalog' as the
                    // session catalog. Remove when the platform ships full 3-part support
                    def CATALOGS_REQUIRING_SPARK_CATALOG_ALIAS = ['hudi', 'delta', 'hive'] as Set
                    def effectiveCatalog = { String catalogType, String userSuppliedName ->
                        if (CATALOGS_REQUIRING_SPARK_CATALOG_ALIAS.contains(catalogType.toLowerCase())) {
                            return 'spark_catalog'
                        }
                        return userSuppliedName
                    }

                    // Both engines exist; ENABLE_AUTHZ decides which one this build hits.
                    def profileName = params.ENABLE_AUTHZ ? 'watsonx_authz_test' : 'watsonx_test'
                    def qsName      = params.ENABLE_AUTHZ ? 'dbt-authz-qs'       : 'dbt-standard-qs'
                    def targetEngineDisplay = params.ENABLE_AUTHZ ? env.SPARK_ENGINE_AUTHZ_NAME : env.SPARK_ENGINE_NAME

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
                        def effective   = effectiveCatalog(catalogType, catalogName)
                        catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
                            withEnv([
                                "QS_NAME=${qsName}",
                                "CATALOG_TYPE=${catalogType}",
                                "CATALOG_NAME=${catalogName}",
                                "EFFECTIVE_CATALOG=${effective}",
                                "PROFILE_NAME=${profileName}",
                                "TARGET_ENGINE_DISPLAY=${targetEngineDisplay}"
                            ]) {
                                sh '''
                                    set -euo pipefail
                                    set +x
                                    export HOME="${WORKSPACE}/.home"
                                    # shellcheck disable=SC1091
                                    source "${WORKSPACE}/.venv/bin/activate"

                                    # Fresh token — the previous stage's may have aged out.
                                    AUTH_BODY=$(printf '{"username":"%s","password":"%s"}' "${CPD_USERNAME}" "${CPD_PASSWORD}")
                                    AUTH_TOKEN=$(curl -s -k -X POST \
                                        "${WATSONX_HOSTNAME}/icp4d-api/v1/authorize" \
                                        -H "Content-Type: application/json" \
                                        -d "${AUTH_BODY}" \
                                        | jq -r '.token // empty')

                                    # Resolve engine id + query server id by display name.
                                    ENGINE_ID=$(curl -s -k -X GET \
                                        "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines" \
                                        -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                        -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \
                                        | jq -r --arg n "${TARGET_ENGINE_DISPLAY}" \
                                            '.spark_engines[]? | select(.display_name==$n) | .id // .engine_id' \
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

        // Print a small summary and publish junit XMLs from every pytest run.
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

    // Always runs, on success or failure. Deletes this build's engines and any
    // catalogs this build created (reused ones are never touched), then purges
    // the workspace.
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

                            # Engines are unique-named per build — delete every id the marker recorded.
                            # shellcheck disable=SC1091
                            source "${WORKSPACE}/pipeline/marker_utils.sh"
                            while IFS= read -r ENGINE_ID; do
                                [ -z "$ENGINE_ID" ] && continue
                                echo "[teardown] deleting Spark engine $ENGINE_ID"
                                curl -s -k -X DELETE \
                                    "${WATSONX_HOSTNAME}/lakehouse/api/${LAKEHOUSE_API_VERSION}/${WATSONX_INSTANCE_ID}/spark_engines/${ENGINE_ID}" \
                                    -H "Authorization: Bearer ${AUTH_TOKEN}" \
                                    -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" || true
                            done < <(marker_get_engine_ids "${WORKSPACE}/.pipeline-marker.json")
                        else
                            echo "[teardown] no marker file; nothing to clean up"
                        fi

                        rm -rf "${WORKSPACE}/.venv" "${WORKSPACE}/.home" \
                               "${WORKSPACE}/adapter/.env" "${WORKSPACE}/.env" \
                               "${WORKSPACE}/adapter" "${WORKSPACE}/.pipeline-marker.json"
                    '''
                }
            } // node
        }
    }
}
