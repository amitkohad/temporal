# Optional observability
Staging defaults create no Log Analytics workspace or metric alerts. Azure platform metrics remain available; paid Log Analytics ingestion requires explicit opt-in, with 30-day retention and 0.1 GiB daily ingestion quota. The quota is an ingestion control, not a spending guarantee. Diagnostic settings and AKS Container Insights are not enabled implicitly.

Metric alerts accept existing scopes, metric namespace/name, aggregation, operator, threshold, and real owner action-group IDs. Empty destinations are rejected. Alerts may incur charges and must be deliberately configured before runtime acceptance. No fictitious notification destinations or production monitoring assurances are supplied.

Validate with `terraform init -backend=false`, `terraform validate`, and `terraform test`.
Optional diagnostic_targets maps resource IDs to explicit supported log_categories and metrics categories. Diagnostic settings are created only when Log Analytics is enabled. Discover supported Azure resource categories before passing them; no allLogs or metrics category is assumed. IDs are structurally validated, while Azure checks existence and category support at apply time.
