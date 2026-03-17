# Securing S3 Access

This is a companion repository for the article "[Securing S3 Objects: Backend Proxy vs Gateway Auth vs Presigned URLs](https://georg-schwarz.com/blog/securing-s3-objects-backend-proxy-gateway-auth-presigned-urls/)".

This repository demonstrates three different approaches to securing access to a
[Garage](https://garagehq.deuxfleurs.fr/) S3-compatible storage API deployed on
Kubernetes. Each example deployment lives in its own directory under `helm/examples/` and can
be deployed independently on top of the shared infrastructure defined in the
`helm/` charts.

The examples share a common demo backend in the `backend` directory. It provides the following endpoints:
- `api/login` to get a JWT.
- `api/01-backend-proxy/file/{fileId}` endpoint for example 01.
- `api/02-gateway-auth/authz` endpoint for example 02.
- `api/03-presigned-uri/file/{fileId}` endpoint for example 03.

## How to run

Prerequisites:
- `kubectl`, `helm`
- One local Kubernetes setup:
  - [`minikube`](https://minikube.sigs.k8s.io/docs/start) and `docker`, or
  - [Rancher Desktop](https://rancherdesktop.io/) with Kubernetes enabled and `nerdctl`

Setup:

If you need to reset a broken local install before trying again, run:

```bash
./uninstall.sh
```

### Option A: Minikube

**1. Start minikube**
```bash
minikube start
```

**2. Build the backend image into minikube's Docker registry**
```bash
eval $(minikube docker-env)
docker build -t securing-s3-access/backend:latest ./backend
eval $(minikube docker-env -u)
```

**3. Open a minikube tunnel** (in a separate terminal - keeps the LoadBalancer IP alive)
```bash
sudo minikube tunnel
```

**4. Install all charts**
```bash
# Installs infrastructure components (Envoy Gateway, Garage operator, Garage instance)
# and all three example apps. The script also builds required Helm dependencies.
./install.sh
```

**5. Validate it works**
```bash
# Fires requests at all examples to verify that:
# - Unauthenticated users are blocked
# - Authenticated but unauthorized users are blocked
# - Authenticated and authorized users have access
GATEWAY_URL="http://127.0.0.1" ./test-access.sh
```

### Option B: Rancher Desktop + nerdctl

**1. Verify Rancher Desktop Kubernetes is active**
```bash
kubectl config current-context
# Expected: rancher-desktop
```

**2. Build the backend image into Rancher Desktop's k3s image store**
```bash
nerdctl --namespace k8s.io build -t securing-s3-access/backend:latest ./backend
```

**3. Install all charts**
```bash
# Installs infrastructure components (Envoy Gateway, Garage operator, Garage instance)
# and all three example apps. The script also builds required Helm dependencies.
./install.sh
```

**4. Discover the Gateway URL**
```bash
kubectl get gateway envoy-ingress -n default
```

Use the `ADDRESS` value shown there, for example `http://192.168.64.2`.

**5. Validate it works**
```bash
# Fires requests at all examples to verify that:
# - Unauthenticated users are blocked
# - Authenticated but unauthorized users are blocked
# - Authenticated and authorized users have access
GATEWAY_URL="http://192.168.64.2" ./test-access.sh
```

## License

MIT - see [LICENSE](./LICENSE)
