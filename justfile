# Dagster on AKS → Azure Databricks POC
# Run `just --list` to see all commands. The .env file is loaded automatically.

set dotenv-load
set dotenv-required := false

export PATH := home_directory() / ".local/bin:" + env("PATH")

# ── Phase runners (guided setup) ─────────────────────────────────────────────

# Run a phase of the setup guide (0-5); re-running skips completed steps
phase n:
    scripts/phases/phase-{{ n }}.sh

# ── Setup ────────────────────────────────────────────────────────────────────

# Install all CLI tools from .tool-versions
setup-tools:
    scripts/setup-tools.sh

# Detect env values and scaffold all keys into .env (--interactive for prompts)
setup-env *ARGS:
    scripts/setup-env.sh {{ ARGS }}

# Set a single key in .env
set-env key value:
    scripts/setup-env.sh set {{ key }} {{ value }}

# Capture terraform outputs into .env
collect-tf stack:
    scripts/setup-env.sh collect-tf {{ stack }}

# Capture pipeline ID into .env after bundle deploy
collect-bundle env:
    scripts/setup-env.sh collect-bundle {{ env }}

# Print current .env values
show-env:
    @scripts/setup-env.sh show

# Install ARC self-hosted runners on AKS (idempotent; teardown: just setup-arc teardown)
setup-arc *ARGS:
    scripts/setup-arc.sh {{ ARGS }}

# Sync .env to GitHub repo variables + create environments for CI/CD
setup-ci *ARGS:
    scripts/setup-ci.sh {{ ARGS }}

# ── Terraform ────────────────────────────────────────────────────────────────

# terraform init (stack: bootstrap, shared, env-stage, env-prod)
tf-init stack *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    _backend() {
      echo "-backend-config=storage_account_name=${TF_BACKEND_STORAGE_ACCOUNT:?Run just collect-tf bootstrap first}" \
           "-backend-config=resource_group_name=${TF_BACKEND_RESOURCE_GROUP:?}" \
           "-backend-config=container_name=tfstate"
    }
    case "{{ stack }}" in
      bootstrap) terraform -chdir=infra/bootstrap init {{ ARGS }} ;;
      shared)    terraform -chdir=infra/shared init $(_backend) -backend-config="key=shared.tfstate" {{ ARGS }} ;;
      env-stage) TF_DATA_DIR="$(pwd)/infra/env/.terraform-stage" terraform -chdir=infra/env init $(_backend) -backend-config="key=stage.tfstate" {{ ARGS }} ;;
      env-prod)  TF_DATA_DIR="$(pwd)/infra/env/.terraform-prod"  terraform -chdir=infra/env init $(_backend) -backend-config="key=prod.tfstate" {{ ARGS }} ;;
      *) echo "Unknown stack '{{ stack }}'. Use: bootstrap, shared, env-stage, env-prod." >&2; exit 1 ;;
    esac

# terraform plan (stack: bootstrap, shared, env-stage, env-prod)
tf-plan stack *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ stack }}" in
      bootstrap) terraform -chdir=infra/bootstrap plan {{ ARGS }} ;;
      shared)    terraform -chdir=infra/shared plan {{ ARGS }} ;;
      env-stage) export TF_VAR_databricks_host="${DBX_STAGE_HOST:-}"
                 export TF_VAR_aks_egress_ip="${AKS_EGRESS_IP:?AKS_EGRESS_IP is blank in .env}"
                 TF_DATA_DIR="$(pwd)/infra/env/.terraform-stage" terraform -chdir=infra/env plan -var-file=stage.tfvars {{ ARGS }} ;;
      env-prod)  export TF_VAR_databricks_host="${DBX_PROD_HOST:-}"
                 export TF_VAR_aks_egress_ip="${AKS_EGRESS_IP:?AKS_EGRESS_IP is blank in .env}"
                 TF_DATA_DIR="$(pwd)/infra/env/.terraform-prod"  terraform -chdir=infra/env plan -var-file=prod.tfvars {{ ARGS }} ;;
      *) echo "Unknown stack '{{ stack }}'. Use: bootstrap, shared, env-stage, env-prod." >&2; exit 1 ;;
    esac

# terraform apply (stack: bootstrap, shared, env-stage, env-prod)
tf-apply stack *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ stack }}" in
      bootstrap) terraform -chdir=infra/bootstrap apply {{ ARGS }} ;;
      shared)    terraform -chdir=infra/shared apply {{ ARGS }} ;;
      env-stage) export TF_VAR_databricks_host="${DBX_STAGE_HOST:-}"
                 export TF_VAR_aks_egress_ip="${AKS_EGRESS_IP:?AKS_EGRESS_IP is blank in .env}"
                 TF_DATA_DIR="$(pwd)/infra/env/.terraform-stage" terraform -chdir=infra/env apply -var-file=stage.tfvars {{ ARGS }} ;;
      env-prod)  export TF_VAR_databricks_host="${DBX_PROD_HOST:-}"
                 export TF_VAR_aks_egress_ip="${AKS_EGRESS_IP:?AKS_EGRESS_IP is blank in .env}"
                 TF_DATA_DIR="$(pwd)/infra/env/.terraform-prod"  terraform -chdir=infra/env apply -var-file=prod.tfvars {{ ARGS }} ;;
      *) echo "Unknown stack '{{ stack }}'. Use: bootstrap, shared, env-stage, env-prod." >&2; exit 1 ;;
    esac

# ── Helm ─────────────────────────────────────────────────────────────────────

# Deploy Dagster via Helm with per-user values from .env
helm-upgrade env *ARGS:
    scripts/helm-upgrade.sh {{ env }} {{ ARGS }}

# ── Databricks Bundle ────────────────────────────────────────────────────────

# Deploy the Databricks Asset Bundle (sets DATABRICKS_HOST from .env)
bundle-deploy env *ARGS:
    scripts/bundle-deploy.sh {{ env }} {{ ARGS }}

# Validate the bundle without deploying
bundle-validate env:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ env }}" = stage ]; then
      export DATABRICKS_HOST="${DBX_STAGE_HOST:?DBX_STAGE_HOST is blank in .env}"
    else
      export DATABRICKS_HOST="${DBX_PROD_HOST:?DBX_PROD_HOST is blank in .env}"
    fi
    cd databricks && databricks bundle validate -t {{ env }}

# ── dbt ──────────────────────────────────────────────────────────────────────

# Run dbt commands against an environment (e.g. just dbt stage build)
dbt env *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ env }}" = stage ]; then
      export DATABRICKS_HOST="${DBX_STAGE_HOST:-}"
      export DBX_WAREHOUSE_HTTP_PATH="${DBX_STAGE_WAREHOUSE_HTTP_PATH:-}"
      export DBX_SP_CLIENT_ID="${DBX_STAGE_SP_CLIENT_ID:-}"
      export DBX_CATALOG=stage
      export DAGSTER_ENV=stage
    elif [ "{{ env }}" = prod ]; then
      export DATABRICKS_HOST="${DBX_PROD_HOST:-}"
      export DBX_WAREHOUSE_HTTP_PATH="${DBX_PROD_WAREHOUSE_HTTP_PATH:-}"
      export DBX_SP_CLIENT_ID="${DBX_PROD_SP_CLIENT_ID:-}"
      export DBX_CATALOG=prod
      export DAGSTER_ENV=prod
    else
      echo "env must be 'stage' or 'prod'" >&2; exit 1
    fi
    if [ -z "${DBX_SP_SECRET:-}" ]; then
      export DBX_SP_SECRET="$(az keyvault secret show \
        --vault-name "${KV_NAME}" \
        --name "dbx-{{ env }}-sp-secret" \
        --query value -o tsv)"
    fi
    cd dbt && ../dagster/.venv/bin/dbt {{ ARGS }}

# ── Dagster ──────────────────────────────────────────────────────────────────

# Check Dagster definitions
check-defs:
    cd dagster && uv run dg check defs

# Run Dagster tests
test:
    cd dagster && uv run pytest

# ── Verification ────────────────────────────────────────────────────────────

# Verify a phase is complete before proceeding (phase: 0-5)
verify phase:
    scripts/verify.sh {{ phase }}

# ── Operations ───────────────────────────────────────────────────────────────

# Port-forward to the Dagster UI (http://localhost:3000)
port-forward env:
    scripts/port-forward.sh {{ env }}

# Run the post-deploy smoke test
smoke-test env:
    scripts/smoke-test.sh {{ env }}

# Stop AKS and Postgres (cost control — floor ~$35-40/mo)
stop:
    scripts/stop.sh

# Start AKS and Postgres
start:
    scripts/start.sh

# Delete AKS entirely to minimize idle cost (floor ~$15/mo); recreate with `just standup`
teardown:
    scripts/teardown.sh

# Recreate AKS + restart Postgres after a teardown (~10-15 min)
standup:
    scripts/standup.sh

# Destroy ALL provisioned resources (start fresh; -y to skip prompts)
destroy-all *ARGS:
    scripts/destroy-all.sh {{ ARGS }}
