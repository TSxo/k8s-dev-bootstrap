set shell := ["bash", "-euo", "pipefail", "-c"]

# ==============================================================================
# Settings
# ==============================================================================

# Every kubectl call is pinned to the Kind cluster's context, so a recipe can
# never act on whichever cluster happens to be current.
cluster := env("CLUSTER_NAME", "dev-cluster")
kubectl := f"kubectl --context kind-{{ cluster }}"

# Argo CD syncs from Git, so this must point at a pushed revision.
repo_url := env("REPO_URL", "https://github.com/TSxo/k8s-dev-bootstrap.git")

# Host ports. The gateway port is also fixed in bootstrap/kind-config.yaml.
gateway_port := "8080"
argo_ui_port := env("ARGO_UI_PORT", "8081")

# Schema validation: built-in kinds, plus a community catalogue for CRDs such as
# Application, Gateway and HTTPRoute. `lint` skips Argo CD's upstream CRDs,
# because kubeconform has no schema for the CustomResourceDefinition kind itself.
crd_catalog := "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main"
crd_schema := crd_catalog + "/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
kubeconform := f"kubeconform -strict -summary -schema-location default -schema-location '{{ crd_schema }}'"

# ==============================================================================
# Meta and Defaults
# ==============================================================================

# Display available recipes.
default:
    @just --list

# ==============================================================================
# Lifecycle
# ==============================================================================

# Check that the required tools are installed and Docker is running.
[group("lifecycle")]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    for tool in docker kind kubectl curl; do
        command -v "$tool" >/dev/null || { echo "error: $tool is not installed (see README)" >&2; exit 1; }
    done
    docker info >/dev/null 2>&1 || { echo "error: Docker is not running" >&2; exit 1; }

# Create the cluster, install Argo CD and sync everything from Git at `revision`.
[group("lifecycle")]
up revision="main": check cluster-create argo-install (argo-bootstrap revision) argo-wait
    @echo
    @echo "Ready."
    @echo "  Argo CD UI:  just argo-ui        (then http://localhost:{{ argo_ui_port }})"
    @echo "  Demo app:    just demo           (or http://demo.localhost:{{ gateway_port }})"
    @echo "  Password:    just argo-password  (user: admin)"

# Delete the cluster and everything in it.
[group("lifecycle")]
down: cluster-delete

# ==============================================================================
# Cluster
# ==============================================================================

# Create the Kind cluster (no-op if it already exists).
[group("cluster")]
cluster-create:
    kind get clusters | grep -qx "{{ cluster }}" || \
        kind create cluster --name "{{ cluster }}" --config bootstrap/kind-config.yaml --wait 120s

# Delete the Kind cluster.
[group("cluster")]
cluster-delete:
    kind delete cluster --name "{{ cluster }}"

# ==============================================================================
# Argo CD
# ==============================================================================

# Install the pinned Argo CD release and wait for it to be ready.
[group("argo")]
argo-install:
    {{ kubectl }} apply --server-side --force-conflicts -k bootstrap/argocd
    {{ kubectl }} -n argocd wait --for=condition=Available deployment --all --timeout=5m
    {{ kubectl }} -n argocd rollout status statefulset/argocd-application-controller --timeout=5m

# Apply the root Application, which syncs platform/app-of-apps from Git at `revision`.
[group("argo")]
argo-bootstrap revision="main":
    sed -E \
        -e 's#^( *repoURL: ).*#\1"{{ repo_url }}"#' \
        -e 's#^( *(targetRevision|revision): ).*#\1"{{ revision }}"#' \
        bootstrap/root-app.yaml \
        | {{ kubectl }} apply -f -

# Wait until the root Application, and so every child, is Synced and Healthy.
[group("argo")]
argo-wait:
    {{ kubectl }} -n argocd wait application/root \
        --for=jsonpath='{.status.sync.status}'=Synced \
        --for=jsonpath='{.status.health.status}'=Healthy --timeout=10m

# Port-forward the Argo CD UI to localhost (HTTP; TLS is disabled for local use).
[group("argo")]
argo-ui:
    @echo "Argo CD UI: http://localhost:{{ argo_ui_port }}  (user: admin, password: just argo-password)"
    {{ kubectl }} -n argocd port-forward svc/argocd-server {{ argo_ui_port }}:80

# Decode and display the initial Argo CD admin password.
[group("argo")]
argo-password:
    @{{ kubectl }} -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 --decode && echo

# ==============================================================================
# Inspection
# ==============================================================================

# Show nodes, Argo CD Applications, Gateway API resources and pods.
[group("inspect")]
status:
    {{ kubectl }} get nodes -o wide
    -{{ kubectl }} -n argocd get applications
    -{{ kubectl }} get gatewayclasses,gateways,httproutes -A
    {{ kubectl }} get pods -A

# Call the demo app through the gateway.
[group("inspect")]
demo:
    curl --fail --silent --show-error --max-time 10 \
        --retry 30 --retry-delay 2 --retry-all-errors \
        -H "Host: demo.localhost" "http://127.0.0.1:{{ gateway_port }}/"

# ==============================================================================
# Quality
# ==============================================================================

# Lint YAML and workflows, check justfile formatting, and validate every rendered manifest.
[group("quality")]
lint:
    yamllint --strict .
    actionlint
    just --fmt --check
    kubectl kustomize bootstrap/argocd | {{ kubeconform }} -skip CustomResourceDefinition
    helm template root platform/app-of-apps | {{ kubeconform }}
    {{ kubeconform }} bootstrap/root-app.yaml platform/gateway apps
