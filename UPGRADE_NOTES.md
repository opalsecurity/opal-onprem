# Modernization notes (branch: modernize-terraform-stack)

This branch responds to a customer review that flagged this repo as badly out
of date. Summary of changes, by original comment:

1. **RDS Postgres 15.10 (EOL May 2026)** - replaced by moving to Aurora
   PostgreSQL (see #7); if you stay on plain RDS Postgres instead, bump
   `engine_version` to a current supported release (17.x as of mid-2026 -
   check https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.DBVersions.html).
2. **k8s 1.32 (standard support ended Mar 2026, extended support only)** -
   `variable.cluster_version` default bumped to 1.35. This ages fast; check
   https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
   before every deploy.
3. **AWS provider 4.67 -> 6.43+** - `main.tf` now requires `>= 6.43, < 7.0`.
   This is a 2 major-version jump; review the v5 and v6 upgrade guides on the
   registry for resource-level breaking changes beyond what's covered here.
4. **EKS module 18.31.0 -> ~> 21.0** - also a multi-major jump. v21 removed
   aws-auth configmap management entirely, so this branch switches cluster
   auth to EKS access entries (`authentication_mode = "API"`,
   `access_entries` block in `eks.tf`).
5. **EKS Auto Mode** - enabled via `cluster_compute_config` in `eks.tf`. This
   replaces the hand-rolled VPC CNI / EBS CSI / AWS Load Balancer Controller
   IRSA roles and Helm release, and the `eks_managed_node_group*` config, all
   of which have been deleted. `main.tf` no longer configures the
   `kubernetes`/`helm` providers since nothing in this repo uses them anymore.

   **Post-merge finding:** `module.eks.node_security_group_id`, which
   `eks.tf` previously used for the node-to-RDS security group rule, does
   not correspond to the security group Auto Mode nodes actually use - Auto
   Mode nodes attach to AWS's auto-created cluster security group instead.
   This was silently broken (the rule attached to an unused SG, causing RDS
   connection timeouts with no obvious error) until fixed by switching to
   `module.eks.cluster_primary_security_group_id`. If you see connection
   timeouts to RDS from cluster workloads after a fresh apply, check this
   first.
6. **Write-only password + ephemeral Secrets Manager** - `rds.tf` generates
   the master password with an `ephemeral "random_password"` resource,
   stores it in Secrets Manager via `secret_string_wo`, and feeds it to the
   database via `master_password_wo` / `master_password_wo_version`. The
   plaintext password is never written to state or plan files, and the old
   `rds_password` sensitive output (which held the cleartext value) has been
   removed from `outputs.tf` in favor of `rds_password_secret_arn`.
   Requires Terraform >= 1.11.
7. **Aurora PostgreSQL vs RDS Postgres** - `rds.tf` now provisions an
   `aws_rds_cluster` (1 writer + `var.db_reader_count` readers) instead of a
   single `aws_db_instance`. Aurora fails over to a reader in ~30s;
   RDS Postgres Multi-AZ has no automatic failover between instances.

## Manual steps required after `terraform apply`

EKS Auto Mode provides the underlying capability for two things but does not
auto-configure them - both require a one-time manual `kubectl apply` against
the live cluster before deploying any PVC- or Ingress-using workload (e.g.
before installing Opal via KOTS):

1. **Default StorageClass** - Auto Mode registers the EBS CSI driver but
   creates no StorageClass pointing at it. Without one, PVC-backed
   workloads (KOTS's own datastore, Opal's app) hang `Pending` indefinitely.
2. **IngressClass / IngressClassParams** - Auto Mode won't provision an ALB
   for any Ingress until these exist; AWS's own docs confirm this isn't
   automatic even under Auto Mode.

Both are intentionally *not* managed in this Terraform: doing so requires
the `kubernetes` provider, which needs network access to the cluster's
private API endpoint (`endpoint_public_access = false`), meaning every
future `apply` - even ones unrelated to these two resources - would only
work from inside the VPC. See the comment block in `main.tf` for the exact
manifests and rationale.

## Things that still need a human before you `terraform apply`

- **This is not a safe in-place upgrade for an existing deployed cluster/DB.**
  These are suggested changes for review, not a tested migration plan.
- **RDS -> Aurora is a data migration, not a version bump.** Terraform will
  want to destroy the `aws_db_instance` and create a new `aws_rds_cluster`.
  Plan an actual migration (snapshot restore into Aurora, or logical
  dump/restore) and cut Opal over during a maintenance window.
- **VPC module bumped 3.2.0 -> ~> 6.0** (not one of the 7 items, but the old
  version isn't validated against AWS provider 6.x and would likely break
  planning). This also jumps several majors - diff the plan carefully.
- **EKS module 18 -> 21 + Auto Mode + access entries is three changes at
  once** on the cluster's control plane and auth model. Consider sequencing
  these as separate applies against a non-prod cluster first.
- Version numbers here (provider/module versions, k8s version, Aurora
  version) were current as of mid-2026 research for this branch - re-check
  the registry/AWS docs for anything newer before applying.

## Follow-ups (not urgent, tracked for later)

- **Opal's setup doc is now out of date for the `kubectl get pods -A` step.**
  It documents the old self-managed node group output (`aws-node`,
  `ebs-csi-controller`, `ebs-csi-node`, `kube-proxy` DaemonSets across 3
  nodes). With Auto Mode enabled, none of those run as visible workloads -
  Auto Mode manages networking and storage internally - so the real output
  is just `coredns` pods (2 here) and nothing else. This is expected, not a
  bug, but the doc should be updated so it doesn't look like a failed
  deployment to the next person following it.
- **Opal's KOTS-packaged Ingress is incompatible with EKS Auto Mode.** Its
  Helm chart configures the ALB via the legacy
  `kubernetes.io/ingress.class: alb` annotation and
  `alb.ingress.kubernetes.io/*` annotations - both silently ignored/
  unrecognized by Auto Mode, which requires `spec.ingressClassName` plus a
  separate `IngressClassParams` resource for scheme/certificate config.
  Workaround in use: disable Opal's "pre-packaged K8s ingress" in the KOTS
  config and manage the Ingress independently (see runbook / ask John for
  the manifest). Worth reporting to Opal as a packaging gap - likely
  affects GKE Autopilot similarly.