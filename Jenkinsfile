// Multi-Catalog Integration Tests (AuthZ & Non-AuthZ) for dbt-watsonx-spark.
// Design doc: docs/superpowers/specs/2026-08-13-jenkins-dbt-watsonx-pipeline-design.md
// Implementation plan: docs/superpowers/plans/2026-08-13-jenkins-dbt-watsonx-pipeline.md

pipeline {
    agent { label 'linux' }

    parameters {
        choice(name: 'DEPLOYMENT_FORM', choices: ['CPD', 'SAAS'], description: 'Target deployment platform')
        booleanParam(name: 'ENABLE_AUTHZ', defaultValue: true, description: 'Run with AuthZ enabled')
        booleanParam(name: 'SKIP_INFRA', defaultValue: false, description: 'True: skip catalog+engine creation, assume they exist (uses run_test.sh). False: full stack (uses run_catalog_tests.sh).')
        string(name: 'ICEBERG_CATALOG_NAME', defaultValue: 'iceberg_data', description: 'Iceberg catalog name. Empty to skip Iceberg.')
        string(name: 'HUDI_CATALOG_NAME', defaultValue: 'hudi_data', description: 'Hudi catalog name. Empty to skip Hudi.')
        string(name: 'DELTA_CATALOG_NAME', defaultValue: 'delta_data', description: 'Delta catalog name. Empty to skip Delta.')
        string(name: 'HIVE_CATALOG_NAME', defaultValue: '', description: 'Reserved for future. Ignored in v1.')
        booleanParam(name: 'DELETE_CATALOG_AFTER_TEST', defaultValue: true, description: 'Delete only catalogs this run created')
        string(name: 'LAKEHOUSE_CONSOLE_VERSION', defaultValue: '2.2.x', description: 'For traceability; incorporated into engine name')
        string(name: 'DBT_ADAPTER_BRANCH', defaultValue: 'main', description: 'git ref of dbt-watsonx-spark to test')
        string(name: 'ADAPTER_REPO_URL', defaultValue: 'https://github.com/roneymathew/dbt-watsonx-spark.git', description: 'Adapter git URL')
        string(name: 'TIMEOUT_MINUTES', defaultValue: '90', description: 'Overall build timeout')
    }

    options {
        timeout(time: params.TIMEOUT_MINUTES.toInteger(), unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        WATSONX_HOSTNAME     = credentials('wx-host')
        WATSONX_APIKEY       = credentials('wx-apikey')
        WATSONX_INSTANCE_ID  = credentials('wx-instance-id')
        CPD_USERNAME         = credentials('wx-username')
    }

    stages {
        stage('Validate params') {
            steps {
                script {
                    def anyCatalog = [params.ICEBERG_CATALOG_NAME, params.HUDI_CATALOG_NAME, params.DELTA_CATALOG_NAME]
                        .any { it?.trim() }
                    if (!anyCatalog) {
                        error 'At least one of ICEBERG_CATALOG_NAME, HUDI_CATALOG_NAME, DELTA_CATALOG_NAME must be non-empty.'
                    }
                    if (!(params.DEPLOYMENT_FORM in ['CPD', 'SAAS'])) {
                        error "DEPLOYMENT_FORM must be CPD or SAAS, got: ${params.DEPLOYMENT_FORM}"
                    }
                    if (params.SKIP_INFRA && params.DEPLOYMENT_FORM == 'SAAS') {
                        error 'SKIP_INFRA=true is not supported with DEPLOYMENT_FORM=SAAS (run_test.sh is CPD-only).'
                    }
                    echo "Params validated: deployment=${params.DEPLOYMENT_FORM}, authz=${params.ENABLE_AUTHZ}, skip_infra=${params.SKIP_INFRA}"
                }
            }
        }
        stage('Checkout adapter') {
            steps {
                sh '''
                    set -euo pipefail
                    rm -rf "${WORKSPACE}/adapter"
                    git clone --depth 1 --branch "'''+"${params.DBT_ADAPTER_BRANCH}"+'''" \\
                        "'''+"${params.ADAPTER_REPO_URL}"+'''" "${WORKSPACE}/adapter"
                    (cd "${WORKSPACE}/adapter" && git log -1 --oneline)
                '''
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
                sh '''
                    set -euo pipefail
                    set +x
                    export HOME="${WORKSPACE}/.home"
                    export ICEBERG_CATALOG_NAME="'''+"${params.ICEBERG_CATALOG_NAME}"+'''"
                    export HUDI_CATALOG_NAME="'''+"${params.HUDI_CATALOG_NAME}"+'''"
                    export DELTA_CATALOG_NAME="'''+"${params.DELTA_CATALOG_NAME}"+'''"
                    bash "${WORKSPACE}/pipeline/write_env.sh" "${WORKSPACE}/adapter/.env"
                '''
            }
        }
        stage('Run given script (infra + Iceberg pytest)') {
            steps {
                sh '''
                    set -euo pipefail
                    export HOME="${WORKSPACE}/.home"
                    # Deploy the given scripts into the adapter checkout so their SCRIPT_DIR/..
                    # resolves to the adapter root (where tests/ lives).
                    mkdir -p "${WORKSPACE}/adapter/scripts"
                    cp -f "${WORKSPACE}/scripts/run_test.sh" "${WORKSPACE}/adapter/scripts/run_test.sh"
                    cp -f "${WORKSPACE}/scripts/run_catalog_tests.sh" "${WORKSPACE}/adapter/scripts/run_catalog_tests.sh"
                    chmod +x "${WORKSPACE}/adapter/scripts/"*.sh

                    # Initialize marker
                    # shellcheck disable=SC1091
                    source "${WORKSPACE}/pipeline/marker_utils.sh"
                    marker_init "${WORKSPACE}/.pipeline-marker.json" "'''+"${env.BUILD_TAG}"+'''"

                    # Activate venv and cd to adapter root
                    # shellcheck disable=SC1091
                    source "${WORKSPACE}/.venv/bin/activate"
                    cd "${WORKSPACE}/adapter"

                    if [ "'''+"${params.SKIP_INFRA}"+'''" = "true" ]; then
                        SCRIPT="./scripts/run_test.sh"
                    else
                        SCRIPT="./scripts/run_catalog_tests.sh"
                    fi

                    # ENABLE_AUTHZ is threaded via env — the given scripts do not read it directly,
                    # but the pipeline's later stages will select the right query server profile.
                    export ENABLE_AUTHZ="'''+"${params.ENABLE_AUTHZ}"+'''"

                    "$SCRIPT"
                '''
            }
        }
        stage('Per-catalog pytest sweep (Hudi/Delta)') {
            steps {
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
                            sh '''
                                set -euo pipefail
                                export HOME="${WORKSPACE}/.home"
                                # shellcheck disable=SC1091
                                source "${WORKSPACE}/.venv/bin/activate"

                                # Re-authenticate and look up the query server URI.
                                # (We don't source the given scripts because their main() runs on source.)
                                AUTH_TOKEN=$(curl -s -k -X POST \\
                                    "${WATSONX_HOSTNAME}/icp4d-api/v1/authorize" \\
                                    -H "Content-Type: application/json" \\
                                    -d "{\\"username\\":\\"${CPD_USERNAME}\\",\\"api_key\\":\\"${WATSONX_APIKEY}\\"}" \\
                                    | jq -r .token)

                                ENGINE_ID=$(curl -s -k -X GET \\
                                    "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines" \\
                                    -H "Authorization: Bearer ${AUTH_TOKEN}" \\
                                    -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \\
                                    | jq -r ".spark_engines[]? | select(.display_name==\\"${SPARK_ENGINE_NAME}\\") | .id // .engine_id" \\
                                    | head -n1)

                                QS_ID=$(curl -s -k -X GET \\
                                    "${WATSONX_HOSTNAME}/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines/${ENGINE_ID}/query_servers" \\
                                    -H "Authorization: Bearer ${AUTH_TOKEN}" \\
                                    -H "LhInstanceId: ${WATSONX_INSTANCE_ID}" \\
                                    | jq -r ".query_servers[]? | select(.query_server_details.name==\\"'''+"${qsName}"+'''\\") | .id" \\
                                    | head -n1)

                                export WATSONX_URI="/lakehouse/api/v3/${WATSONX_INSTANCE_ID}/spark_engines/${ENGINE_ID}/query_servers/${QS_ID}/connect/cliservice"
                                export WATSONX_CATALOG="'''+"${effective}"+'''"
                                export WATSONX_SCHEMA="wxd_schema"
                                export WATSONX_HOST="${WATSONX_HOSTNAME}"
                                export WATSONX_INSTANCE="${WATSONX_INSTANCE_ID}"
                                export WATSONX_USER="${CPD_USERNAME}"
                                export PROFILE_NAME="'''+"${profileName}"+'''"
                                export ADAPTER_ROOT="${WORKSPACE}/adapter"
                                export PYTEST_TEST_PATTERN="tests/functional/adapter/catalog_tests/"

                                echo "[sweep] catalog_type='''+"${catalogType}"+''' effective=${WATSONX_CATALOG}"
                                bash "${WORKSPACE}/pipeline/run_pytest_for_catalog.sh"
                            '''
                        }
                    }
                }
            }
        }
        stage('Report') {
            steps {
                sh '''
                    set -euo pipefail
                    echo "=== Build summary ==="
                    echo "deployment=${DEPLOYMENT_TYPE} authz='''+"${params.ENABLE_AUTHZ}"+'''"
                    echo "engine=${SPARK_ENGINE_NAME}"
                    if [ -f "${WORKSPACE}/.pipeline-marker.json" ]; then
                        cat "${WORKSPACE}/.pipeline-marker.json"
                    fi
                '''
                junit allowEmptyResults: true, testResults: 'adapter/**/junit*.xml'
            }
        }
    }

    post {
        always {
            echo 'TODO: implement teardown in Task 10'
        }
    }
}
