# databricks/
Databricks Asset Bundle. Targets `stage` and `prod`. Contains the SDP pipeline only.
`databricks bundle validate -t stage` must pass in CI without credentials to a workspace? (It needs host; CI logs in via OIDC.)
See docs/04-conventions.md (Bundle section) and runbook 3.2.
