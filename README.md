# Argo CD Bootstrap

This repo bootstraps Argo CD in three phases:

1. `bootstrap-core`
2. `bootstrap-kro-definitions`
3. one provider chart such as `bootstrap-provider-local` or `bootstrap-provider-aws`

`bootstrap-core` installs the shared controllers. `bootstrap-kro-definitions` installs the `kro` `ResourceGraphDefinition`s that define the provider APIs. Provider charts then create instances of those APIs instead of carrying their own wait jobs.

## Layout

- `charts/bootstrap-core/`
  Installs the common controllers and waits for their CRDs and controllers to become ready.
- `charts/bootstrap-kro-definitions/`
  Installs the `kro` RGDs that define the provider bootstrap APIs.
- `charts/bootstrap-provider-local/`
  Creates a `LocalBootstrap` instance plus the local token source secret.
- `charts/bootstrap-provider-aws/`
  Creates an `AwsBootstrap` instance.
- `argocd-apps/<provider>/<cluster-name>/`
  Git-managed Argo app trees.
- `local/`
  Local-only lab assets: fixture manifests, smoke app, generated assets, and the recreate script.
- `docs/adr/`
  One ADR describing the current bootstrap design.

## Install Order

Install the charts in order:

```bash
helm upgrade --install bootstrap-core ./charts/bootstrap-core -n kube-system
helm upgrade --install bootstrap-kro-definitions ./charts/bootstrap-kro-definitions -n kube-system
helm upgrade --install bootstrap-provider-aws ./charts/bootstrap-provider-aws -n kube-system
```

The external tool is responsible for ordering:

- wait for `ConfigMap/bootstrap-core-complete`
- install `bootstrap-kro-definitions`
- wait for the required RGDs to become `Active`
- install one provider chart
- wait for `ConfigMap/bootstrap-complete`

## What Each Phase Owns

- `bootstrap-core`
  Installs Argo CD, External Secrets Operator, and `kro`, then waits for their CRDs and controllers.
- `bootstrap-kro-definitions`
  Defines:
  - `LocalBootstrap`
  - `AwsBootstrap`
- provider charts
  Create provider instances only. The resource fanout and readiness rules live in the RGDs.

## Local Lab

The local lab uses two `k3d` clusters:

- `external-services`
  Hosts the fake external secret source and a private Git server.
- `argocd-bootstrapper`
  Runs Argo CD, External Secrets Operator, and `kro`.

Use [recreate-lab.sh](/Users/mwatson/Documents/projects/personal/k8skro/repo/local/recreate-lab.sh):

```bash
./local/recreate-lab.sh
```

That script:

1. recreates both clusters
2. applies [external-services.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/local/fixtures/external-services.yaml)
3. packages `bootstrap-core`, `bootstrap-kro-definitions`, and `bootstrap-provider-local`
4. seeds `bootstrap-core` into the main cluster
5. waits for `ConfigMap/bootstrap-core-complete`
6. installs `bootstrap-kro-definitions`
7. waits for `ResourceGraphDefinition/local-bootstrap` to become `Active`
8. installs `bootstrap-provider-local`
9. waits for `ConfigMap/bootstrap-complete`
10. applies [repo-auth-smoke.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/local/smoke/repo-auth-smoke.yaml)

The local provider flow is:

- `bootstrap-core` installs ESO
- `bootstrap-kro-definitions` defines `LocalBootstrap`
- `bootstrap-provider-local` creates a `LocalBootstrap` instance
- `kro` expands that into:
  - `Secret/eso-token`
  - `SecretStore/kubernetes-local-secrets`
  - `ExternalSecret/argocd-sso-secret`
  - `ExternalSecret/local-private-repo`
  - `Application/root`
  - `ConfigMap/bootstrap-complete`

## Notes

- Provider charts no longer contain wait jobs.
- The provider completion signal is produced by the `kro` resource graph, not by a provider hook job.
- `bootstrap-core` is still imperative because it installs controllers and waits for their CRDs and controllers.
- The local repo-auth smoke app is separate from the root app tree and lives in [repo-auth-smoke.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/local/smoke/repo-auth-smoke.yaml).
- The Git-managed root app tree for the local cluster lives under [argocd-apps/local/argocd-bootstrapper/root](/Users/mwatson/Documents/projects/personal/k8skro/repo/argocd-apps/local/argocd-bootstrapper/root).
- The local root app tree now includes [kro.yaml](/Users/mwatson/Documents/projects/personal/k8skro/repo/argocd-apps/local/argocd-bootstrapper/root/kro.yaml) so `kro` is handed over to Git alongside Argo CD and External Secrets.

## Decision Record

See [ADR 0001](/Users/mwatson/Documents/projects/personal/k8skro/repo/docs/adr/0001-bootstrap-core-and-wrappers.md).
