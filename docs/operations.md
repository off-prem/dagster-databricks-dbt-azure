# Day-to-day operations

Commands and workflows for after setup is complete.
For initial setup, see the [setup guide](guide.md) or just run `just phase 0` through `just phase 5`.

---

## Cost control

```bash
just stop     # stop AKS + Postgres when done for the day (~2-3 min)
just start    # restart when ready to work (~3-5 min)
```

Three levels, depending on how long you'll be away:

| Command | Idle cost | Recovery | When to use |
|---------|-----------|----------|-------------|
| `just stop` | ~$35-40/mo | `just start` (~3-5 min) | Overnight, weekends |
| `just teardown` | ~$15/mo | `just standup` (~10-15 min) | Gone for a week+ |
| `just destroy-all` | $0 | Re-run from `just phase 0` | Starting fresh |

See [stop/start](concepts/stop-start.md) for gotchas.

---

## Common workflows

### View the Dagster UI

```bash
just port-forward stage    # http://localhost:3000
just port-forward prod     # same, for prod
```

The UI is ClusterIP only (no public ingress) — `port-forward` is the only way to reach it.

### Run dbt

```bash
just dbt stage build        # build all models
just dbt stage run          # run models without tests
just dbt stage test         # run tests only
just dbt stage build --select silver_posts   # one model
```

The `just dbt` wrapper auto-fetches the SP secret from Key Vault and sets all
required env vars. No manual export needed.

### Deploy code changes

After modifying Dagster code or dbt models:

```bash
# Rebuild the Docker image (includes Dagster + dbt)
az acr build --registry "$(just show-env | grep ACR_NAME | cut -d= -f2 | tr -d '"')" \
  --image poc:latest --file dagster/Dockerfile .

# Redeploy
just helm-upgrade stage
just bundle-deploy stage    # if Databricks extract code changed
```

CI does this automatically on merge to main (see [CI/CD](concepts/cicd.md)).

### Run the smoke test

```bash
just smoke-test stage    # launches raw_posts → bronze → silver, waits for success
```

### Validate without deploying

```bash
just check-defs              # Dagster definitions
just bundle-validate stage   # Databricks bundle
just verify <N>              # verify phase N is healthy (read-only, no changes)
```

---

## Re-running phases

Phase runners are idempotent — re-running skips completed steps:

```bash
just phase 2    # checks each step, skips what's done, runs what's not
```

This is useful after:
- A failure partway through (fix the issue, re-run)
- Changing `.env` values (re-run to propagate)
- Adding resources that a phase creates

---

## IP changes

Your public IP is stored in `.env` as `TF_VAR_my_ip_cidr` and used in firewall
rules and Databricks IP access lists. When your IP changes:

```bash
just setup-env                # re-detects your public IP
just tf-apply shared          # updates Postgres/AKS firewall rules
just tf-apply env-stage       # updates Databricks IP access list
just tf-apply env-prod        # same for prod
```

---

## Syncing CI variables

After any terraform apply that changes outputs, re-sync to GitHub:

```bash
just setup-ci    # reads .env, pushes all values to GitHub repository variables
```

---

## Full command reference

Run `just --list` for the complete list. Key commands:

| Command | What it does |
|---------|-------------|
| **Phase runners** | |
| `phase <N>` | Run a setup phase (0-5); skips completed steps |
| **Setup** | |
| `setup-tools` | Install all CLIs from `.tool-versions` |
| `setup-env` | Detect env values, scaffold `.env` (`--interactive` for prompts) |
| `set-env <key> <value>` | Set a single key in `.env` |
| `show-env` | Print current `.env` values |
| `setup-ci` | Sync `.env` to GitHub variables and create environments |
| `setup-arc` | Install self-hosted GitHub runners (ARC) on AKS |
| **Terraform** | |
| `tf-init <stack>` | `terraform init` (bootstrap, shared, env-stage, env-prod) |
| `tf-plan <stack>` | `terraform plan` |
| `tf-apply <stack>` | `terraform apply` |
| `collect-tf <stack>` | Capture Terraform outputs into `.env` |
| **Deploy** | |
| `helm-upgrade <env>` | Deploy Dagster via Helm |
| `bundle-deploy <env>` | Deploy the Databricks Asset Bundle |
| `bundle-validate <env>` | Validate bundle without deploying |
| **dbt + Dagster** | |
| `dbt <env> <args>` | Run dbt commands against an environment |
| `check-defs` | Check Dagster definitions |
| `test` | Run Dagster tests |
| **Operations** | |
| `port-forward <env>` | Dagster UI at localhost:3000 |
| `smoke-test <env>` | Post-deploy smoke test |
| `verify <phase>` | Verify a phase is complete (read-only) |
| `stop` / `start` | Stop/start AKS + Postgres |
| `teardown` / `standup` | Delete/recreate AKS for lower idle cost |
| `destroy-all` | Destroy all provisioned resources |
