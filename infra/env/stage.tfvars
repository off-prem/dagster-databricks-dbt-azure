# Filled during Phase 0–2. IDs only, never secrets.
env             = "stage"
location        = "eastus2"
subscription_id = ""        # Phase 0.1
tenant_id       = ""        # Phase 0.1
my_ip_cidr      = ""        # x.x.x.x/32 — for authorized IP ranges / firewalls
shared_rg       = "rg-dagsterpoc-shared"
aks_name        = "aks-dagsterpoc"
metastore_id    = ""        # Phase 2.3 (first env creates it)
