# ADR 0001: Bootstrap Core, Definitions, And Provider Instances

## Status

Accepted

## Context

Bootstrapping Argo CD has three different concerns:

- installing shared controllers and waiting for them to become usable
- defining a stable bootstrap API across environments
- instantiating environment-specific bootstrap resources

The previous split of `bootstrap-core` plus provider charts was an improvement over one large bootstrap job, but the provider charts still carried environment-specific resource fanout and wait logic. That kept the provider layer noisy and made repeated bootstrap patterns harder to standardize.

## Decision

Use three phases:

1. `bootstrap-core`
2. `bootstrap-kro-definitions`
3. one provider chart

`bootstrap-core` remains imperative. It installs the shared controllers, currently:

- Argo CD
- External Secrets Operator
- `kro`

and waits for their CRDs and controllers to be ready.

`bootstrap-kro-definitions` installs `kro` `ResourceGraphDefinition`s that define the provider bootstrap APIs:

- `LocalBootstrap`
- `AwsBootstrap`

Provider charts create instances of those APIs and any small input resources they need. They do not carry provider wait jobs.

Use `argocd-apps/<provider>/<cluster-name>/` for the Git-managed Argo application trees so the directory structure clearly shows both environment and cluster scope.

Keep `local/` as the home for local-only fixtures, scripts, smoke apps, and generated artifacts.

## Consequences

Positive:

- provider charts shrink to instance charts instead of mini-orchestrators
- repeated bootstrap patterns can be standardized through RGDs
- provider readiness moves into the resource graph instead of bespoke shell logic
- the local and cloud-specific flows can share the same high-level contract

Negative:

- bootstrap now has an explicit definitions phase
- `kro` itself becomes part of the day-0 controller set
- the external installer must handle the order `core -> kro-definitions -> provider`

## Notes

- `bootstrap-core` still writes `ConfigMap/bootstrap-core-complete`.
- Provider completion still uses `ConfigMap/bootstrap-complete`, but it is now produced by the `kro` graph rather than a provider hook job.
- This ADR does not move Argo CD installation itself into `kro`; day-0 controller install and CRD/controller waits remain imperative in `bootstrap-core`.
