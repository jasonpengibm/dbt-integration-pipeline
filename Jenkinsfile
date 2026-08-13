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
                echo 'TODO: implement in Task 8'
            }
        }
        stage('Run given script (infra + Iceberg pytest)') {
            steps {
                echo 'TODO: implement in Task 8'
            }
        }
        stage('Per-catalog pytest sweep (Hudi/Delta)') {
            steps {
                echo 'TODO: implement in Task 9'
            }
        }
        stage('Report') {
            steps {
                echo 'TODO: implement in Task 9'
            }
        }
    }

    post {
        always {
            echo 'TODO: implement teardown in Task 10'
        }
    }
}
