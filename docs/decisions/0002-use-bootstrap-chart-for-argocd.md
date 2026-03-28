# ADR 0002: Use A Bootstrap Helm Chart For Argo CD

## Status

Accepted

Supersedes ADR 0001.

## Context

The bootstrap process must work the same way across local `k3d` clusters and managed Kubernetes clusters such as GKE, EKS, and AKS.

The key ownership requirement is that Argo CD should manage itself after bootstrap. If an external tool such as Terraform or CDK continues to own the Argo CD Helm release, Argo CD upgrades from Git will drift against the external state and the external tool will try to push Argo CD back to the old configuration.

At the same time, the bootstrap process still needs ordering:

- install Argo CD
- wait until Argo CD is actually ready to reconcile
- apply repository secrets, projects, and root applications

Earlier prototypes showed that a plain initial `Application` or a Helm `post-install` `extraObjects` approach could still race `argocd-repo-server`.

## Decision

Use a dedicated bootstrap Helm chart with a one-shot post-install job.

That chart:

1. is the only object installed by an external tool
2. installs Argo CD from inside the cluster via a hook job
3. waits for Argo CD readiness
4. applies bootstrap Argo CD resources from bundled ConfigMaps
5. creates a sentinel `ConfigMap` to mark bootstrap completion

The bootstrap chart does not manage Argo CD as a normal dependency or release-owned resource after bootstrap. Its only job is to get the cluster to the point where Argo CD can manage itself from Git.

The chart also supports a mode where Argo CD installation is skipped entirely and the job only waits for an existing Argo CD deployment before applying the bootstrap resources. This covers platforms where Argo CD is provided externally or preinstalled.

## Why This Over `kro`

`kro` solved the ordering problem, but it was not adding enough value for this narrower use case.

The real requirement is:

- standard installation across cluster types
- one small day-0 contract
- explicit Argo CD handoff
- no ongoing ownership by Terraform, CDK, or another bootstrap tool

A bootstrap chart plus one small job satisfies that requirement directly.

## Consequences

- Bootstrap is standardized as a single Helm install
- The imperative step is intentionally limited to a one-shot hook job
- The job must be idempotent and protected against reruns
- Chart sources and bootstrap source repositories must remain configurable through chart values
- Argo CD becomes the steady-state owner after bootstrap
