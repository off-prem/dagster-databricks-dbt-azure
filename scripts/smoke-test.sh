#!/usr/bin/env bash
# Post-deploy smoke test (docs/05-cicd.md): port-forward in the background, launch the job
# via GraphQL, poll until SUCCESS/FAILURE, 20-minute timeout. Used by deploy-stage.yml and
# promote-prod.yml after helm upgrade + bundle deploy.
# Usage: scripts/smoke-test.sh <stage|prod>
set -euo pipefail

ENV="${1:?Usage: scripts/smoke-test.sh <stage|prod>}"
case "${ENV}" in
  stage|prod) ;;
  *) echo "env must be 'stage' or 'prod'" >&2; exit 1 ;;
esac

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

NAMESPACE="dagster-${ENV}"
RELEASE="dagster-${ENV}"
SERVICE="${RELEASE}-dagster-webserver"
LOCAL_PORT="${PORT:-3000}"
GRAPHQL_URL="http://localhost:${LOCAL_PORT}/graphql"

# TODO(Phase 2.5/3.5): these names don't exist yet.
# - JOB_NAME: docs/05-cicd.md names it "bronze_silver_job" but that job still needs to be
#   defined in dagster/src/poc/definitions.py (wrapping bronze_<source> + silver_<model>).
# - REPO_LOCATION / REPO_NAME: set by dagster/pyproject.toml + dg code location config
#   (Phase 2.5 scaffold). Confirm with `dg check defs` or the GraphQL `workspaceOrError` query
#   once the code location exists, then update the defaults below.
JOB_NAME="${JOB_NAME:-bronze_silver_job}"
REPO_LOCATION="${REPO_LOCATION:-poc}"
REPO_NAME="${REPO_NAME:-__repository__}"

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"

PF_PID=""
cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Starting background port-forward to ${SERVICE} (namespace ${NAMESPACE})..."
kubectl port-forward -n "${NAMESPACE}" "svc/${SERVICE}" "${LOCAL_PORT}:80" \
  >/tmp/dagster-smoke-port-forward.log 2>&1 &
PF_PID=$!

echo "Waiting for the webserver to answer..."
for i in $(seq 1 30); do
  if curl -sf -o /dev/null "http://localhost:${LOCAL_PORT}"; then
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "Webserver never came up; see /tmp/dagster-smoke-port-forward.log" >&2
    exit 1
  fi
  sleep 2
done

echo "Launching run for job '${JOB_NAME}' (location=${REPO_LOCATION}, repo=${REPO_NAME})..."
LAUNCH_QUERY='mutation($location: String!, $repo: String!, $job: String!) {
  launchRun(executionParams: {
    selector: {
      repositoryLocationName: $location
      repositoryName: $repo
      jobName: $job
    }
  }) {
    __typename
    ... on LaunchRunSuccess { run { runId } }
    ... on PythonError { message }
    ... on RunConfigValidationInvalid { errors { message } }
    ... on PipelineNotFoundError { message }
  }
}'

LAUNCH_BODY=$(jq -n \
  --arg q "${LAUNCH_QUERY}" \
  --arg location "${REPO_LOCATION}" \
  --arg repo "${REPO_NAME}" \
  --arg job "${JOB_NAME}" \
  '{query: $q, variables: {location: $location, repo: $repo, job: $job}}')

LAUNCH_RESPONSE=$(curl -sf -X POST "${GRAPHQL_URL}" \
  -H "Content-Type: application/json" \
  -d "${LAUNCH_BODY}")

RUN_ID=$(echo "${LAUNCH_RESPONSE}" | jq -r '.data.launchRun.run.runId // empty')
if [[ -z "${RUN_ID}" ]]; then
  echo "Failed to launch run:" >&2
  echo "${LAUNCH_RESPONSE}" | jq . >&2
  exit 1
fi

echo "Launched run ${RUN_ID}. Polling for completion (timeout ${TIMEOUT_SECONDS}s)..."

STATUS_QUERY='query($runId: ID!) {
  runOrError(runId: $runId) {
    __typename
    ... on Run { status }
    ... on RunNotFoundError { message }
    ... on PythonError { message }
  }
}'

ELAPSED=0
while (( ELAPSED < TIMEOUT_SECONDS )); do
  BODY=$(jq -n --arg q "${STATUS_QUERY}" --arg runId "${RUN_ID}" \
    '{query: $q, variables: {runId: $runId}}')
  RESPONSE=$(curl -sf -X POST "${GRAPHQL_URL}" -H "Content-Type: application/json" -d "${BODY}")
  STATUS=$(echo "${RESPONSE}" | jq -r '.data.runOrError.status // empty')

  case "${STATUS}" in
    SUCCESS)
      echo "Run ${RUN_ID} succeeded."
      exit 0
      ;;
    FAILURE|CANCELED)
      echo "Run ${RUN_ID} ended with status ${STATUS}." >&2
      exit 1
      ;;
    *)
      echo "Run ${RUN_ID} status: ${STATUS:-UNKNOWN}. Waiting..."
      ;;
  esac

  sleep "${POLL_INTERVAL}"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo "Timed out after ${TIMEOUT_SECONDS}s waiting for run ${RUN_ID}." >&2
exit 1
