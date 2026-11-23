# Local Kubernetes GitOps Environment

[![CI](https://github.com/TSxo/k8s-dev-bootstrap/actions/workflows/ci.yaml/badge.svg)](https://github.com/TSxo/k8s-dev-bootstrap/actions/workflows/ci.yaml)

**What this demonstrates:** one command creates a local
[Kind](https://kind.sigs.k8s.io/) cluster and installs
[Argo CD](https://argo-cd.readthedocs.io/). From then on, Argo CD installs
everything else from this Git repository: a
[Gateway API](https://gateway-api.sigs.k8s.io/) implementation
([Envoy Gateway](https://gateway.envoyproxy.io/)) and an example app.

## How it works

`just up` runs these steps:

1. Create the Kind cluster: `bootstrap/kind-config.yaml`.
2. Install Argo CD: `bootstrap/argocd/`.
3. Apply the root Application: `bootstrap/root-app.yaml`.

Argo CD then renders the Helm chart in `platform/app-of-apps/` and syncs its
children in waves:

4. Wave -1: the `platform` and `apps` AppProjects (`templates/projects.yaml`).
5. Wave 0: `envoy-gateway` (platform): the controller and Gateway API CRDs.
6. Wave 1: `gateway` (platform): `platform/gateway/`.
7. Wave 2: `demo` (apps): `apps/demo/`.

Only the first three steps are imperative. Everything after the root Application
is declared in Git and reconciled by Argo CD, so a change under `platform/` or
`apps/` reaches the cluster when it is pushed.

### Repository layout

| Directory    | Contents                                                       | Applied by                           |
| ------------ | -------------------------------------------------------------- | ------------------------------------ |
| `bootstrap/` | Kind config, Argo CD install, root Application                 | `just up` (the only imperative step) |
| `platform/`  | The app-of-apps chart and cluster services such as the gateway | Argo CD, `platform` project          |
| `apps/`      | Workloads, one folder each                                     | Argo CD, `apps` project              |

The two Argo CD
[AppProjects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
make the split enforceable.

- **`platform`** may create cluster-scoped resources (CRDs, GatewayClasses,
  webhooks) in any namespace.
- **`apps`** may pull only from this repository, deploy only to the namespaces
  listed in `platform/app-of-apps/values.yaml`, and create only Deployments,
  Services, ServiceAccounts, ConfigMaps and HTTPRoutes. A workload cannot
  install a CRD, change the gateway, or deploy into `argocd`.

To add a workload: create `apps/<name>/`, add its namespace to
`apps.namespaces`, and add an Application to `platform/app-of-apps/templates/`
modelled on `demo.yaml`.

### How CI tests the commit under test

The child Applications take their Git revision from a Helm value rather than
hard-coding `main`. `just argo-bootstrap <revision>` writes the revision into
the root Application, which passes it to the chart as `revision`, and each
template renders `targetRevision: {{ .Values.revision | quote }}`. Every layer
(the root, the chart and each child's manifests) is fetched from the same
commit.

> [!IMPORTANT] 
> Argo CD syncs from the Git remote. Local edits take effect only after you push 
> them and run `just up <branch-or-sha>`. To sync a fork, set `REPO_URL`.

## How a request reaches the demo app

1. The browser requests `demo.localhost:8080`, which resolves to
   `127.0.0.1:8080` on your machine.
2. The kind port mapping forwards it to port 30080 on the Kind node
   (`bootstrap/kind-config.yaml`).
3. The NodePort Service forwards it to the Envoy pod on port 10080
   (`platform/gateway/envoyproxy.yaml`).
4. Envoy matches the `Host` header against the HTTPRoutes and picks
   `apps/demo/httproute.yaml`.
5. The route sends it to Service `whoami:80` (`apps/demo/service.yaml`).
6. The Service forwards it to the whoami pod on port 8080
   (`apps/demo/deployment.yaml`).

Envoy listens on 10080 inside the pod because Envoy Gateway shifts privileged
ports (below 1024) up by 10000, so the proxy does not need root. The number
30080 must match in two places: `containerPort` in `bootstrap/kind-config.yaml`
and `nodePort` in `platform/gateway/envoyproxy.yaml`.

### What applies, in order

1. **Cluster creation:** `bootstrap/kind-config.yaml` publishes the node's port
   30080 on `127.0.0.1:8080`. This is fixed when the cluster is created.
2. **Wave 0:** `platform/app-of-apps/templates/envoy-gateway.yaml` installs the
   Envoy Gateway controller and the CRDs that define `GatewayClass`, `Gateway`,
   `HTTPRoute` and `EnvoyProxy`. 
3. **Wave 1:** `platform/app-of-apps/templates/gateway.yaml` syncs
   `platform/gateway/`:
    - `envoyproxy.yaml`: how to run Envoy. Its Service is a NodePort, fixed to
      30080 by a patch, because Envoy Gateway generates that Service and has no
      field for the port number.
    - `gatewayclass.yaml`: the class `eg`. Envoy Gateway implements it, using
      the `EnvoyProxy` settings above.
    - `gateway.yaml`: the Gateway `eg`, an HTTP listener on port 80 that accepts
      routes from any namespace. When the controller sees it, it creates an
      Envoy Deployment and its NodePort Service in `envoy-gateway-system`.
    - `argocd-route.yaml`: routes `argocd.localhost` to the Argo CD UI.
4. **Wave 2:** `platform/app-of-apps/templates/demo.yaml` syncs `apps/demo/`:
    - `deployment.yaml` and `service.yaml`: the whoami app on port 80.
    - `httproute.yaml`: attaches to the Gateway through `parentRefs` (Gateway
      `eg` in `envoy-gateway-system`) and sends `demo.localhost` to `whoami:80`.
      The controller pushes the route into the running Envoy; no restart.

Within a wave, the order does not matter: the controller reconciles whatever
exists and fills in the rest as it arrives.

## Prerequisites

Works on macOS and Linux.

- A Docker daemon: [Docker Desktop](https://docs.docker.com/desktop/),
  [OrbStack](https://orbstack.dev/),
  [Colima](https://github.com/abiosoft/colima) or Docker Engine on Linux.
- [just](https://just.systems/),
  [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation),
  [kubectl](https://kubernetes.io/docs/tasks/tools/) and curl.

Either install those yourself, or use the Nix dev shell, which provides
everything except Docker:

```bash
nix develop
```

`just check` reports anything missing.

## Quick start

```bash
just up
```

`up` waits until the root Application, and therefore every Application under it,
is `Synced` and `Healthy`. Then:

| What                       | How                                        |
| -------------------------- | ------------------------------------------ |
| Argo CD UI                 | `just argo-ui`, then http://localhost:8081 |
| Argo CD UI via the gateway | http://argocd.localhost:8080               |
| Admin password             | `just argo-password` (user `admin`)        |
| Demo app                   | `just demo`, or http://demo.localhost:8080 |
| Tear down                  | `just down`                                |

Names ending in `.localhost` resolve to `127.0.0.1` in browsers without editing
`/etc/hosts`. `just demo` sends the `Host` header explicitly, so it works with
any curl.

Argo CD serves plain HTTP (`server.insecure`), and the gateway port is bound to
`127.0.0.1` only. This setup is for local development; do not reuse it on a
shared cluster.

## Recipes

Run `just` to list them, grouped.

| Group     | Recipes                                                   |
| --------- | --------------------------------------------------------- |
| lifecycle | `check`, `up [revision]`, `down`                          |
| cluster   | `cluster-create`, `cluster-delete`                        |
| argo      | `argo-install`, `argo-bootstrap [revision]`, `argo-wait`, |
|           | `argo-ui`, `argo-password`                                |
| inspect   | `status`, `demo`                                          |
| quality   | `lint`                                                    |

`up` runs `check`, `cluster-create`, `argo-install`, `argo-bootstrap` and
`argo-wait` in that order. Every `kubectl` call is pinned to the
`kind-dev-cluster` context, so no recipe can act on another cluster even if it
is your current context.

## Configuration

| Setting                 | Where                                     | Default         |
| ----------------------- | ----------------------------------------- | --------------- |
| Cluster name            | `CLUSTER_NAME` env var                    | `dev-cluster`   |
| Git source for Argo CD  | `REPO_URL` env var                        | this repository |
| Argo CD UI port-forward | `ARGO_UI_PORT` env var                    | `8081`          |
| Gateway host port       | `bootstrap/kind-config.yaml` (`hostPort`) | `8080`          |
| Component versions      | see below                                 |                 |

## Pinned versions

| Component             | Version                                                                                                                                     | Pinned in                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| kind                  | v0.33.0                                                                                                                                     | `flake.lock`                          |
| Kubernetes node image | v1.37.0 (by digest, built for kind v0.33.0)                                                                                                 | `bootstrap/kind-config.yaml`          |
| Argo CD               | v3.6.2                                                                                                                                      | `bootstrap/argocd/kustomization.yaml` |
| Envoy Gateway         | v1.10.0                                                                                                                                     | `platform/app-of-apps/values.yaml`    |
| traefik/whoami        | v1.12.0                                                                                                                                     | `apps/demo/deployment.yaml`           |
| Dev shell tools       | nixpkgs `93a9ed0` (2026-11-21): just 1.59.0, kind 0.33.0, kubectl 1.37.2, Helm 4.3.2, kubeconform 0.8.0, yamllint 1.38.0, actionlint 1.7.12 | `flake.lock`                          |

## Why Gateway API rather than Ingress NGINX

Earlier versions of this repository used Ingress NGINX. The Kubernetes project
[retired it in March 2026](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/):
it no longer receives releases or security fixes. Gateway API is the recommended
successor, and Envoy Gateway is a conformant implementation of it. Kind has no
load balancer, so Envoy is exposed on a fixed NodePort that
`bootstrap/kind-config.yaml` maps to `127.0.0.1:8080`.

## License

MIT. See [LICENSE](LICENSE).
