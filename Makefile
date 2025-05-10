# ------------------------------------------------------------------------------
# This project uses Docker and Brew:
#
# - https://docs.docker.com/engine/
# - https://docs.docker.com/desktop/
# - https://brew.sh/

# ------------------------------------------------------------------------------
# Variables

KIND_CLUSTER    := dev-cluster
KIND_CONFIG     := kind-config.yaml
INGRESS         := https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
ARGO            := https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
ARGO_INGRESS    := manifests/argocd-ingress.yaml
ARGO_CMD_CM     := manifests/argocd-cmd-params-cm.yaml
ARGO_NS         := argocd

.DEFAULT_GOAL   := help

# ------------------------------------------------------------------------------
# Helpers

## help: Print this help message
.PHONY: help
help:
	@echo "Usage:"
	@sed -n "s/^##//p" $(MAKEFILE_LIST) | column -t -s ":" |  sed -e "s/^/ /"

# ------------------------------------------------------------------------------
# Install Dependencies

## tooling: Install the required brew packages
.PHONY: tooling
tooling:
	brew update
	brew list kind || brew install kind
	brew list kubectl || brew install kubectl
	brew list argocd || brew install argocd

# ------------------------------------------------------------------------------
# Setup Cluster

## cluster/up: Starts the Kind cluster
.PHONY: cluster/up
cluster/up:
	@kind create cluster --name $(KIND_CLUSTER) --config $(KIND_CONFIG)

## cluster/down: Deletes the Kind cluster
.PHONY: cluster/down
cluster/down:
	@kind delete cluster --name $(KIND_CLUSTER)

# ------------------------------------------------------------------------------
# Setup Ingress

## ingress: Adds an Ingress NGINX controller to the cluster
.PHONY: ingress
ingress:
	@kubectl apply -f $(INGRESS)

# ------------------------------------------------------------------------------
# Setup Argo CD

## argo: Adds Argo CD to the cluster
.PHONY: argo
argo:
	@kubectl get ns | grep $(ARGO_NS) || kubectl create namespace $(ARGO_NS)
	@kubectl apply -n $(ARGO_NS) -f $(ARGO)
	@kubectl apply -n $(ARGO_NS) -f $(ARGO_CMD_CM)
	@kubectl apply -n $(ARGO_NS) -f $(ARGO_INGRESS)
	@kubectl rollout restart deployment argocd-server -n $(ARGO_NS)

## argo/password: Retrieve the Argo CD initial admin password
.PHONY: argo/password
argo/password:
	@argocd admin initial-password -n $(ARGO_NS)

# ------------------------------------------------------------------------------
# Status and Inspection

## status/all: Show status of nodes, ingress, and Argo CD
.PHONY: status/all
status/all: status/nodes status/ingress status/argo

## status/nodes: Show status of Kind cluster nodes
.PHONY: status/nodes
status/nodes:
	@kubectl get nodes -o wide

## status/ingress: Show status of Ingress NGINX components
.PHONY: status/ingress
status/ingress:
	@kubectl get all -n ingress-nginx

## status/argo: Show status of Argo CD components
.PHONY: status/argo
status/argo:
	@kubectl get all -n $(ARGO_NS)
	@kubectl get cm -n $(ARGO_NS)
