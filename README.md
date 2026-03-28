# Argo CD Bootstrapper

This repository bootstraps Argo CD through a thin seed layer and uses `kro` to order the first Argo resources correctly.

The current flow is:

1. K3s auto-deploys one Argo CD `HelmChart`
2. K3s auto-deploys one seed `Job`
3. The seed job installs `kro` and waits for the required CRDs
4. The seed job applies a `kro` `ResourceGraphDefinition` and one `ArgoBootstrap` resource
5. `kro` waits for Argo CD readiness and only then creates the initial `root` `Application`
6. That root `Application` syncs the repository app tree

## Repository Layout

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
2. run one seed job that installs `kro` and applies the bootstrap artifacts
3. let `kro` create the initial `root` `Application` only after Argo CD is actually ready
4. let Argo CD sync [clusters/local/root/platform-root.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root/platform-root.yaml)

Example:

```bash
k3d cluster create --config k3d/local-cluster.yaml
kubectl get applications -n argocd
```

## Notes

- The local seed consists of [00-argocd.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed/00-argocd.yaml), [01-bootstrap-seed-rbac.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed/01-bootstrap-seed-rbac.yaml), [02-bootstrap-artifacts.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed/02-bootstrap-artifacts.yaml), and [03-bootstrap-seed-job.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/k3d/seed/03-bootstrap-seed-job.yaml).
- The imperative edge is intentionally tiny: the seed job only installs `kro` and applies the bootstrap RGD/instance after the Argo CD and `kro` APIs exist.
- The real ordering logic lives in `kro`, not in the seed script.
- The current app tree only installs `platform-root`. If you want Argo CD to manage itself later, add a dedicated Argo app to [clusters/local/root](/Users/mwatson/Documents/projects/personal/k8skro/repo/clusters/local/root) and retire the bootstrap `HelmChart` explicitly.

## Decision Record

- The direct Argo-only bootstrap path was evaluated, including a Helm `post-install` hook for the root `Application`.
- That prototype still hit a startup race where the root application reconciled before `argocd-repo-server` was reliably ready.
- The current direction is therefore to use `kro` for bootstrap ordering and keep the imperative seed layer minimal.
- See [ADR 0001](/Users/mwatson/Documents/projects/personal/k8skro/repo/docs/decisions/0001-use-kro-for-bootstrap-ordering.md).
