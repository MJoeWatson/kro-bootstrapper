# ADR 0001: Use `kro` for Bootstrap Ordering

## Status

Accepted

## Context

This repository is bootstrapping Argo CD for local `k3d` and eventually for other Kubernetes clusters.

The simplest-looking option was:

1. install the Argo CD Helm chart
2. create the initial root `Application`
3. let Argo CD take over the rest of the platform

That approach was tested directly in `k3d`, first as a plain manifest and then as a Helm `post-install` hook through `extraObjects`.

The result was still not reliable enough. The root `Application` was created, but the first reconciliation raced `argocd-repo-server` startup and the application entered `ComparisonError` until it was manually refreshed.

This is the relevant failure mode:

- Argo CD resources existed
- the root `Application` object existed
- Argo CD was still not ready to consume that application reliably

So the real bootstrap problem is not just "apply manifests in order". It is "create higher-level Argo resources only after Argo CD is actually ready".

At the same time, bootstrap is already growing beyond a single `Application`. It is expected to include:

- repository credentials and repository secrets
- `AppProject` definitions
- initial root `Application` or app-of-apps resources
- potentially other shared Argo CD bootstrap resources for teams or environments

That makes a small wait script less attractive over time.

## Decision

Use `kro` to model and enforce bootstrap ordering after the seed install, instead of relying on a bootstrap script that waits for Argo CD and then applies follow-up resources.

The intended shape is:

1. seed the cluster with the minimal controllers required for bootstrap
2. use one thin seed job to install `kro` and apply the bootstrap artifacts after the required APIs exist
3. use `kro` to express readiness and ordering for Argo CD bootstrap resources
4. create Argo CD resources only after Argo CD is ready to consume them

## Why Not A Script

A script is simpler only while bootstrap remains tiny.

Once bootstrap includes readiness checks plus multiple related resources, the script becomes an imperative deployment engine:

- readiness logic lives in shell instead of the cluster
- status is hidden in job logs instead of surfaced as Kubernetes resources
- extending bootstrap for more repos, teams, or environments increases script complexity quickly
- reruns and partial failures become harder to reason about

In contrast, `kro` gives:

- explicit ordering
- explicit readiness gates
- a reusable bootstrap API
- observable in-cluster status
- a better path as bootstrap scope grows

The remaining seed job is intentionally small and mechanical. It exists only because:

- `kro` must be installed before `ResourceGraphDefinition` resources can be served
- the Argo CD `Application` CRD must exist before the bootstrap RGD can reference `Application`

That seed job is not the bootstrap engine. It only gets the cluster to the point where `kro` can take over the ordering problem.

## Consequences

- Bootstrap is more structured than a one-off wait script
- The design may look heavier at first glance
- The extra complexity is justified by avoiding the observed Argo CD startup race and by keeping bootstrap declarative as it grows
- Future readers should treat the direct Argo-only bootstrap as an evaluated prototype, not the chosen direction
