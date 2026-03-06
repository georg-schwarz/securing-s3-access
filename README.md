# Securing S3 Access — Tutorial Repository

This repository demonstrates four different approaches to securing access to a
[Garage](https://garagehq.deuxfleurs.fr/) S3-compatible storage API deployed on
Kubernetes. Each example deployment lives in its own directory under `helm/examples/` and can
be deployed independently on top of the shared infrastructure defined in the
`helm/` charts.

The examples share a common demo backend in the `backend` directory. It provides the following endpoints:
- `api/login` to get a JWT.
- `api/01-backend-proxy/file/{fileId}` endpoint for example 01.
- `api/02-gateway-auth/authz` endpoint for example 02.
- `api/03-presigned-uri/file/{fileId}` endpoint for example 03.
- `api/04-temp-credentials/access` endpoint for example 04.

## How to run

Prerequisites:
- [`minikube`](https://minikube.sigs.k8s.io/docs/start), `kubectl`, `helm`, `docker`

Setup:

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

**3. Open a minikube tunnel** (in a separate terminal — keeps the LoadBalancer IP alive)
```bash
sudo minikube tunnel
```

**4. Install all charts**
```bash
# Installs infrastructure components (Envoy Gateway, Garage operator, Garage instance)
# and all three example apps
./install.sh
```

Validate it works:
```bash
# Fires requests at all examples to verify that:
# - Unauthenticated users are blocked
# - Authenticated but unauthorized users are blocked
# - Authenticated and authorized users have access
GATEWAY_URL="http://127.0.0.1" ./test-access.sh
```

## License

MIT - see [LICENSE](./LICENSE)
