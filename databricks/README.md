# databricks/
Databricks Asset Bundle. Targets `stage` and `prod`. Contains the SDP pipeline only.
`databricks bundle validate -t stage` must pass in CI without credentials to a workspace? (It needs host; CI logs in via OIDC.)
See docs/conventions.md (Bundle section) and guide step 3.2.
