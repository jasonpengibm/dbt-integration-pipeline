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
                echo 'TODO: implement in Task 7'
            }
        }
        stage('Checkout adapter') {
            steps {
                echo 'TODO: implement in Task 7'
            }
        }
        stage('Prepare workspace') {
            steps {
                echo 'TODO: implement in Task 7'
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
