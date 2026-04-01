#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_DIR="${REPO_ROOT}/local/generated"
MAIN_SEED_DIR="${GENERATED_DIR}/main-seed"
MAIN_STATIC_DIR="${GENERATED_DIR}/main-static"
MAIN_CONTEXT="k3d-argocd-bootstrapper"
EXTERNAL_CONTEXT="k3d-external-services"
EXTERNAL_API_PORT=6552
EXTERNAL_GIT_PORT=9080

mkdir -p "${MAIN_SEED_DIR}" "${MAIN_STATIC_DIR}/bootstrap"
rm -f "${MAIN_SEED_DIR}"/*.yaml
rm -f "${MAIN_STATIC_DIR}/bootstrap"/*.tgz

k3d cluster delete argocd-bootstrapper >/dev/null 2>&1 || true
k3d cluster delete external-services >/dev/null 2>&1 || true

helm package "${REPO_ROOT}/charts/bootstrap-core" -d "${MAIN_STATIC_DIR}/bootstrap" >/dev/null
helm package "${REPO_ROOT}/charts/bootstrap-kro-definitions" -d "${MAIN_STATIC_DIR}/bootstrap" >/dev/null
helm package "${REPO_ROOT}/charts/bootstrap-provider-local" -d "${MAIN_STATIC_DIR}/bootstrap" >/dev/null

k3d cluster create external-services \
  --servers 1 \
  --agents 0 \
  --api-port "${EXTERNAL_API_PORT}" \
  -p "${EXTERNAL_GIT_PORT}:80@loadbalancer"

kubectl --context "${EXTERNAL_CONTEXT}" apply -f "${REPO_ROOT}/local/fixtures/external-services.yaml" >/dev/null
kubectl --context "${EXTERNAL_CONTEXT}" rollout status deployment/git-http -n repo-auth --timeout=180s >/dev/null

EXTERNAL_CA_BUNDLE="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${EXTERNAL_CONTEXT}\")].cluster.certificate-authority-data}")"
EXTERNAL_BEARER_TOKEN="$(kubectl --context "${EXTERNAL_CONTEXT}" create token eso-remote-reader -n bootstrap-secrets --duration=24h)"
LOCAL_VALUES_CONTENT="$(
  cat <<EOF
bootstrap:
  local:
    remoteServerURL: https://host.docker.internal:${EXTERNAL_API_PORT}
    remoteCABundle: ${EXTERNAL_CA_BUNDLE}
    remoteBearerToken: ${EXTERNAL_BEARER_TOKEN}
    repositoryURL: http://host.docker.internal:${EXTERNAL_GIT_PORT}/repo.git
EOF
)"
LOCAL_VALUES_CONTENT_INDENTED="$(printf '%s\n' "${LOCAL_VALUES_CONTENT}" | sed 's/^/    /')"

cat > "${MAIN_SEED_DIR}/00-bootstrap-core.yaml" <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: bootstrap-core
  namespace: kube-system
spec:
  chart: https://%{KUBERNETES_API}%/static/bootstrap/bootstrap-core-0.1.0.tgz
  targetNamespace: kube-system
  bootstrap: true
  backOffLimit: 1
  timeout: 20m
  failurePolicy: abort
EOF

cat > "${GENERATED_DIR}/bootstrap-provider-local.yaml" <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: bootstrap-provider-local
  namespace: kube-system
spec:
  chart: https://%{KUBERNETES_API}%/static/bootstrap/bootstrap-provider-local-0.1.0.tgz
  targetNamespace: kube-system
  backOffLimit: 1
  timeout: 20m
  failurePolicy: abort
  valuesContent: |-
${LOCAL_VALUES_CONTENT_INDENTED}
EOF

cat > "${GENERATED_DIR}/bootstrap-kro-definitions.yaml" <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: bootstrap-kro-definitions
  namespace: kube-system
spec:
  chart: https://%{KUBERNETES_API}%/static/bootstrap/bootstrap-kro-definitions-0.1.0.tgz
  targetNamespace: kube-system
  backOffLimit: 1
  timeout: 20m
  failurePolicy: abort
EOF

k3d cluster create argocd-bootstrapper \
  --servers 1 \
  --agents 0 \
  --volume "${MAIN_SEED_DIR}:/var/lib/rancher/k3s/server/manifests/bootstrap@server:*" \
  --volume "${MAIN_STATIC_DIR}:/var/lib/rancher/k3s/server/static@server:*"

for _ in $(seq 1 120); do
  if kubectl --context "${MAIN_CONTEXT}" get configmap -n kube-system bootstrap-core-complete >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! kubectl --context "${MAIN_CONTEXT}" get configmap -n kube-system bootstrap-core-complete >/dev/null 2>&1; then
  kubectl --context "${MAIN_CONTEXT}" get configmap -n kube-system
  kubectl --context "${MAIN_CONTEXT}" get jobs -n kube-system
  kubectl --context "${MAIN_CONTEXT}" get pods -n kube-system
  exit 1
fi

kubectl --context "${MAIN_CONTEXT}" apply -f "${GENERATED_DIR}/bootstrap-kro-definitions.yaml" >/dev/null

for _ in $(seq 1 120); do
  if [ "$(kubectl --context "${MAIN_CONTEXT}" get resourcegraphdefinition local-bootstrap -o jsonpath='{.status.state}' 2>/dev/null || true)" = "Active" ] && \
     kubectl --context "${MAIN_CONTEXT}" get crd localbootstraps.bootstrap.k8skro.dev >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if [ "$(kubectl --context "${MAIN_CONTEXT}" get resourcegraphdefinition local-bootstrap -o jsonpath='{.status.state}' 2>/dev/null || true)" != "Active" ] || \
   ! kubectl --context "${MAIN_CONTEXT}" get crd localbootstraps.bootstrap.k8skro.dev >/dev/null 2>&1; then
  kubectl --context "${MAIN_CONTEXT}" get resourcegraphdefinition local-bootstrap -o yaml || true
  kubectl --context "${MAIN_CONTEXT}" get crd | rg 'bootstrap.k8skro.dev|kro.run' || true
  exit 1
fi

kubectl --context "${MAIN_CONTEXT}" wait --for=condition=Established crd/localbootstraps.bootstrap.k8skro.dev --timeout=300s >/dev/null

kubectl --context "${MAIN_CONTEXT}" apply -f "${GENERATED_DIR}/bootstrap-provider-local.yaml" >/dev/null

for _ in $(seq 1 120); do
  if kubectl --context "${MAIN_CONTEXT}" get configmap -n kube-system bootstrap-complete >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! kubectl --context "${MAIN_CONTEXT}" get configmap -n kube-system bootstrap-complete >/dev/null 2>&1; then
  kubectl --context "${MAIN_CONTEXT}" get configmap -n kube-system
  kubectl --context "${MAIN_CONTEXT}" get localbootstraps.bootstrap.k8skro.dev -n kube-system -o yaml || true
  kubectl --context "${MAIN_CONTEXT}" get applications -n argocd || true
  kubectl --context "${MAIN_CONTEXT}" get jobs -n kube-system
  kubectl --context "${MAIN_CONTEXT}" get pods -n kube-system
  kubectl --context "${MAIN_CONTEXT}" get application root -n argocd -o yaml || true
  exit 1
fi

kubectl --context "${MAIN_CONTEXT}" apply -f "${REPO_ROOT}/local/smoke/repo-auth-smoke.yaml" >/dev/null

SYNC_STATUS=""
HEALTH_STATUS=""
for _ in $(seq 1 120); do
  SYNC_STATUS="$(kubectl --context "${MAIN_CONTEXT}" get application repo-auth-smoke -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  HEALTH_STATUS="$(kubectl --context "${MAIN_CONTEXT}" get application repo-auth-smoke -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  if [ "${SYNC_STATUS}" = "Synced" ] && [ "${HEALTH_STATUS}" = "Healthy" ]; then
    break
  fi
  sleep 5
done

if [ "${SYNC_STATUS}" != "Synced" ] || [ "${HEALTH_STATUS}" != "Healthy" ]; then
  kubectl --context "${MAIN_CONTEXT}" get applications -n argocd
  kubectl --context "${MAIN_CONTEXT}" get application repo-auth-smoke -n argocd -o yaml || true
  exit 1
fi

kubectl --context "${MAIN_CONTEXT}" get applications -n argocd
kubectl --context "${MAIN_CONTEXT}" get secret -n argocd local-private-repo -o yaml

printf '\nArgo CD UI: http://127.0.0.1:8080\n'
printf 'External Git URL: http://host.docker.internal:%s/repo.git\n' "${EXTERNAL_GIT_PORT}"
