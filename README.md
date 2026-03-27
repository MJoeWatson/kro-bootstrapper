# Argo CD Bootstrapper

This repository is evaluating Argo CD bootstrap patterns for local `k3d` and eventually other Kubernetes clusters.

The current prototype flow is:

1. K3s auto-deploys one Argo CD `HelmChart`
2. The chart installs Argo CD and its CRDs
3. A Helm `post-install` hook creates the initial `root` `Application`
4. That root `Application` syncs the repository app tree
5. Argo CD takes over the rest of the platform

## Repository Layout

- `seed/`
- `k3d/`
  Local-only helpers for automatically seeding a `k3d` cluster through the K3s manifests directory.
- `clusters/local/root/`
  The initial app-of-apps tree that bootstrap creates.
- `clusters/local/platform-root/`
  A placeholder steady-state platform root.

## k3d Local Flow

For local testing, mount [k3d/seed](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed) into `/var/lib/rancher/k3s/server/manifests`.

The local seed is intentionally small:

1. install Argo CD through a K3s `HelmChart`
2. let Helm create the initial `root` `Application` as a `post-install` hook
3. let Argo CD sync [clusters/local/root/platform-root.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/platform-root.yaml)

Example:

```bash
k3d cluster create --config k3d/local-cluster.yaml
kubectl get applications -n argocd
```

## Notes

- The bootstrap `HelmChart` is the only local day-0 seed in the current prototype.
- The first `Application` is implementation-specific and is embedded in [k3d/seed/00-argocd.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed/00-argocd.yaml) through `extraObjects`.
- The current app tree only installs `platform-root`. If you want Argo CD to manage itself later, add a dedicated Argo app to [clusters/local/root](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root) and retire the bootstrap `HelmChart` explicitly.

## Decision Record

- The direct Argo-only bootstrap path was evaluated, including a Helm `post-install` hook for the root `Application`.
- That prototype still hit a startup race where the root application reconciled before `argocd-repo-server` was reliably ready.
- The current direction is therefore to use `kro` for bootstrap ordering rather than grow a wait script.
- See [ADR 0001](/Users/mwatson/Documents/projects/personal/k8skro/repo/docs/decisions/0001-use-kro-for-bootstrap-ordering.md).
