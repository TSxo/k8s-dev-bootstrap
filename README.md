# Local Kubernetes Development Environment

This repository contains a Makefile to quickly bootstrap a local Kubernetes
development environment using [Kind](https://kind.sigs.k8s.io/), complete with
[Ingress NGINX](https://github.com/kubernetes/ingress-nginx) and
[Argo CD](https://argo-cd.readthedocs.io/en/stable/) for GitOps workflows.

## Prerequisites

Before you begin, ensure you have the following installed on your macOS system:

- [Docker Desktop](https://docs.docker.com/desktop/mac/install/)
- [Homebrew](https://brew.sh/)
- [Make](https://www.gnu.org/software/make/)

## Quick Start

1. Clone this repository
2. Install required tools:
   ```
   make tooling
   ```
3. Start the Kubernetes cluster:
   ```
   make cluster/up
   ```
4. Set up Ingress NGINX:
   ```
   make ingress
   ```
5. Install Argo CD:
   ```
   make argo
   ```
6. Get the Argo CD admin password:
   ```
   make argo/password
   ```

> [!NOTE]
> Each `make` target does not wait for components to become `ready`. Please allow
> each step to complete before proceeding to the next. You can use the
> `make status/<component>` commands (detailed below) to check readiness.

## Environment Details

This setup creates:

- A Kind-based Kubernetes cluster configured for local development.
- Ingress NGINX controller for routing external traffic.
- Argo CD for GitOps-based deployments.

Once set up, Argo CD will be available at http://argo.local

Ensure that `argo.local` resolves to `127.0.0.1` in your hosts (`/etc/hosts`) file.

## Available Commands

### Installation

- `make tooling`: Install required tools via Homebrew (kind, kubectl, argocd).

### Cluster Management

- `make cluster/up`: Create the Kind cluster.
- `make cluster/down`: Delete the Kind cluster.

### Components

- `make ingress`: Install Ingress NGINX controller.
- `make argo`: Install Argo CD.
- `make argo/password`: Retrieve the initial Argo CD admin password.

### Status Checks

- `make status/all`: Show status of all components.
- `make status/nodes`: Show status of cluster nodes.
- `make status/ingress`: Show status of Ingress NGINX.
- `make status/argo`: Show status of Argo CD components.

## Configuration

The environment uses the following configuration files, update them as required:

- `kind-config.yaml`: Kind cluster configuration.
- `manifests/argocd-ingress.yaml`: Ingress configuration for Argo CD.
- `manifests/argocd-cmd-params-cm.yaml`: Command parameters for Argo CD.

Further configuration can be achieved by updating the top-level variables inside
the `Makefile`.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
