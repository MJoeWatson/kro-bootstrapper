# Argo CD Bootstrapper

This repository bootstraps Argo CD through one reusable Helm chart.

The current flow is:

1. an external tool installs one bootstrap chart
2. the bootstrap chart runs a one-shot `post-install` job
3. that job either installs Argo CD from inside the cluster or waits for an existing Argo CD installation
4. the job waits for Argo CD readiness
5. the job optionally installs External Secrets Operator and, for local `k3d`, can emulate an external secret source
6. the job applies bootstrap Argo CD resources such as the root `Application`
7. the job writes a sentinel `ConfigMap` so bootstrap is not rerun accidentally
8. Argo CD takes over steady-state ownership from Git

## Repository Layout

- `charts/argocd-bootstrap/`
  The reusable bootstrap chart that installs Argo CD once and then hands control to Argo CD itself.
- `k3d/`
  Local-only helpers for automatically seeding a `k3d` cluster through the K3s manifests directory and static file server.
- `clusters/local/root/`
  The initial app-of-apps tree that bootstrap creates.
- `clusters/local/platform-root/`
  A placeholder steady-state platform root.

## Standard Install

For a normal cluster, install the bootstrap chart and let it perform the day-0 setup:

```bash
helm upgrade --install argocd-bootstrap ./charts/argocd-bootstrap -n kube-system
```

That chart is the only thing an external tool needs to own.

If the cluster already provides Argo CD, disable the install step and keep only the wait/apply logic:

```bash
helm upgrade --install argocd-bootstrap ./charts/argocd-bootstrap \
  -n kube-system \
  --set bootstrap.argocd.install=false
```

If the external platform also makes the standard Argo rollout checks irrelevant, disable or override them:

```bash
helm upgrade --install argocd-bootstrap ./charts/argocd-bootstrap \
  -n kube-system \
  --set bootstrap.argocd.install=false \
  --set bootstrap.argocd.wait.enabled=false
```

If you also want to skip External Secrets Operator installation because the platform already provides it:

```bash
helm upgrade --install argocd-bootstrap ./charts/argocd-bootstrap \
  -n kube-system \
  --set bootstrap.argocd.install=false \
  --set bootstrap.argocd.wait.enabled=false \
  --set bootstrap.externalSecrets.install=false
```

## k3d Local Flow

For local testing, mount [k3d/seed](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed) into `/var/lib/rancher/k3s/server/manifests` and [k3d/static/bootstrap](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/static/bootstrap) into `/var/lib/rancher/k3s/server/static/bootstrap`.

The local seed is intentionally tiny:

1. K3s auto-deploys one `HelmChart` custom resource
2. that `HelmChart` installs the packaged bootstrap chart from the local K3s static server
3. the bootstrap chart job installs Argo CD, installs External Secrets Operator, and creates a local test secret path for `argocd-sso-secret`
4. Argo CD syncs [clusters/local/root/external-secrets.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/external-secrets.yaml), [clusters/local/root/argocd.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/argocd.yaml), and [clusters/local/root/platform-root.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/platform-root.yaml)

Example:

```bash
mkdir -p k3d/static/bootstrap
helm package charts/argocd-bootstrap -d k3d/static/bootstrap
k3d cluster create --config k3d/local-cluster.yaml
kubectl get applications -n argocd
```

## Notes

- The bootstrap job is a Helm hook, not a permanent controller.
- The completion sentinel is `ConfigMap/argocd-bootstrap-complete` in `kube-system`.
- The job removes its temporary bootstrap ConfigMaps and elevated `ClusterRoleBinding` after a successful run.
- The chart is designed so an external tool owns only the bootstrap mechanism, not the Argo CD release after handoff.
- The main external sources are configurable through values:
  `bootstrap.job.image`, `bootstrap.argocd.repoURL`, `bootstrap.argocd.chart`, `bootstrap.argocd.version`, and `bootstrap.rootApplication.repoURL`.
- External Secrets Operator is bootstrap-installable through `bootstrap.externalSecrets.*`.
- Local `k3d` bootstrap enables `bootstrap.externalSecrets.localTest.enabled=true`, which creates a dummy secret source and materializes `Secret/argocd-sso-secret` in the `argocd` namespace through ESO's Kubernetes provider.
- That local path validates secret delivery for future SSO work, but a real local OIDC provider is still needed to exercise the full login flow.
- The bootstrap step installs ESO CRDs; the Git-managed [external-secrets.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/external-secrets.yaml) app keeps `installCRDs=false` so Argo takes over the controller without fighting preinstalled CRDs.
- Argo readiness checks are configurable through `bootstrap.argocd.wait.*` and can be disabled entirely for externally provided Argo installations.
- The root app tree now includes [argocd.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/argocd.yaml), so Argo CD hands over to a Git-defined self-management app after bootstrap.
- The root app tree also includes [external-secrets.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/external-secrets.yaml), so External Secrets Operator is also handed over to Git.
- The same root app tree still installs [platform-root.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/platform-root.yaml).

## Decision Record

- Direct Argo-only bootstrap was evaluated first and still hit a startup race around `argocd-repo-server`.
- `kro` was then evaluated for ordering, but was more machinery than this bootstrap problem needed.
- The chosen direction is a bootstrap chart with one one-shot job and a completion sentinel.
- See [ADR 0002](/Users/mwatson/Documents/projects/personal/k8skro/repo/docs/decisions/0002-use-bootstrap-chart-for-argocd.md).
