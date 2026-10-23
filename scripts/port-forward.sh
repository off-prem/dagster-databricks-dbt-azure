#!/usr/bin/env bash
# Reach the Dagster UI without any public ingress (non-negotiable, see CLAUDE.md).
# Usage: scripts/port-forward.sh <stage|prod>
set -euo pipefail

ENV="${1:?Usage: scripts/port-forward.sh <stage|prod>}"
case "${ENV}" in
  stage|prod) ;;
  *) echo "env must be 'stage' or 'prod'" >&2; exit 1 ;;
esac

NAMESPACE="dagster-${ENV}"
RELEASE="dagster-${ENV}"
# TODO(Phase 2.6/2.7): confirm this against the actual dagster/dagster Helm chart service
# once it's installed — `kubectl get svc -n ${NAMESPACE}` — the chart's webserver Service
# name follows "<release>-dagster-webserver" as of current chart versions, but pin it here
# if that ever differs.
SERVICE="${RELEASE}-dagster-webserver"
LOCAL_PORT="${PORT:-3000}"

echo "Port-forwarding ${SERVICE} (namespace ${NAMESPACE}) -> http://localhost:${LOCAL_PORT}"
kubectl port-forward -n "${NAMESPACE}" "svc/${SERVICE}" "${LOCAL_PORT}:80"
