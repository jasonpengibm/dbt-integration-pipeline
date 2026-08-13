# dbt-integration-pipeline

Jenkins pipeline that runs `dbt-watsonx-spark` integration tests across catalog types (Iceberg, Hudi, Delta) for one (deployment × authz) combination per build.

## Layout

- `Jenkinsfile` — declarative pipeline
- `scripts/` — team-provided scripts (read-only, do not modify)
- `pipeline/` — pipeline-owned bash helpers
- `tests/` — bats tests for the helpers
- `docs/superpowers/specs/` — design specs
- `docs/superpowers/plans/` — implementation plans

## Running tests locally

```
bats tests/
shellcheck -x pipeline/*.sh
```

## Kicking off a build

In Jenkins, click "Build with Parameters." Defaults run the full Iceberg + Hudi + Delta suite against a CPD instance with AuthZ enabled. Empty a catalog-name field to skip that catalog.

Required Jenkins credential IDs: `wx-host`, `wx-username`, `wx-apikey`, `wx-instance-id`.

## The 3-part naming workaround

Hive/Hudi/Delta catalogs currently require the literal `spark_catalog` as the session catalog at query time (Iceberg supports proper 3-part naming). The workaround lives entirely in one Groovy block in `Jenkinsfile`, delimited by:

```
// === 3-part naming workaround ===
// ...
// === /workaround ===
```

When the platform ships full 3-part support (~est. Nov 2026), delete that block. No other code changes required.

## Parallel-run isolation

Every artifact is workspace-local:
- venv: `${WORKSPACE}/.venv`
- HOME override: `${WORKSPACE}/.home` (makes `~/.dbt` per-build)
- Engine name: `spark-dbt-${BUILD_TAG_SHORT}-${DEPLOYMENT_FORM}-${AUTHZ_MODE}`
- `.env`: `${WORKSPACE}/.env` (mode 600, deleted in post block)

Two concurrent builds with different or same catalog names both run safely. Cleanup only removes catalogs this build created.

## Known limitations

See `docs/superpowers/specs/2026-08-13-jenkins-dbt-watsonx-pipeline-design.md` Section 12.
