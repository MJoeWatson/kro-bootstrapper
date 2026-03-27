# Argo CD Bootstrapper

This repository bootstraps Argo CD directly through K3s/K3d auto-deployed manifests.

The intended flow is:

1. K3s auto-deploys one Argo CD `HelmChart`
2. The chart installs Argo CD and its CRDs
3. K3s auto-deploys one initial `Application` manifest after the CRD exists
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
2. auto-apply the initial `root` `Application` manifest from the same K3s manifests directory
3. let Argo CD sync [clusters/local/root/platform-root.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/platform-root.yaml)

Example:

```bash
k3d cluster create --config k3d/local-cluster.yaml
kubectl get applications -n argocd
```

## Notes

- The bootstrap `HelmChart` is the only local day-0 seed.
- The first `Application` is implementation-specific and lives in [k3d/seed/10-root-application.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed/10-root-application.yaml).
- The current app tree only installs `platform-root`. If you want Argo CD to manage itself later, add a dedicated Argo app to [clusters/local/root](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root) and retire the bootstrap `HelmChart` explicitly.
