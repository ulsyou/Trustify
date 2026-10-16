# FastAPI PostgreSQL Deployment with Docker and Kubernetes

This repository demonstrates two practical ways to run a **FastAPI application with PostgreSQL**:

1. **Docker Compose** for local development
2. **Kubernetes manifests** for a cluster-based deployment

The goal is to show the deployment path of a small backend service from a local containerized setup to a Kubernetes environment. The project focuses on containerization, service-to-service communication, database connectivity, configuration management, secrets, persistent storage, and basic readiness checks.

---

## Repository Structure

```text
postgres-fastapi-deployment/
├── compose-demo/
│   ├── app/
│   │   └── main.py
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── requirements.txt
│
└── k8s-event-api/
    ├── app/
    │   └── main.py
    ├── Dockerfile
    ├── requirements.txt
    └── k8s-yamls/
        ├── namespace.yaml
        ├── configmap.yaml
        ├── secrets.yaml
        ├── pvc.yaml
        ├── postgres-deployment.yaml
        ├── postgres-service.yaml
        ├── fastapi-deployment.yaml
        └── service.yaml
```

---

## What This Project Covers

- Building a Python/FastAPI application as a Docker image
- Running FastAPI and PostgreSQL together with Docker Compose
- Connecting one container to another by service name
- Reading database configuration from environment variables
- Deploying FastAPI and PostgreSQL on Kubernetes
- Using Kubernetes `Deployment`, `Service`, `ConfigMap`, `Secret`, `Namespace`, and `PersistentVolumeClaim`
- Exposing the API with a `NodePort` service
- Checking application and database readiness through API endpoints

---

# Part 1 — Docker Compose Demo

The first part of the project runs a simple FastAPI service and a PostgreSQL database locally with Docker Compose.

## Architecture

```text
Browser / curl
     |
     v
FastAPI container
     |
     v
PostgreSQL container
```

Docker Compose creates both services on the same network. The FastAPI application can reach the database using the database service name:

```python
host=os.getenv("DB_HOST", "db")
```

In the Compose setup, the PostgreSQL service is named `db`, so the application connects to PostgreSQL through `db:5432`.

## Files

```text
compose-demo/
├── app/main.py
├── Dockerfile
├── docker-compose.yml
└── requirements.txt
```

## FastAPI Endpoints

The Compose demo includes a small FastAPI application with these endpoints:

| Endpoint | Method | Description |
|---|---:|---|
| `/` | GET | Checks whether the FastAPI app is running |
| `/health` | GET | Basic application health check |
| `/db-check` | GET | Connects to PostgreSQL and runs `SELECT 1` |

## Dockerfile

The Dockerfile uses a lightweight Python image, installs the dependencies, copies the application code, exposes port `8000`, and starts Uvicorn.

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## docker-compose.yml

The Compose file defines two services:

- `web`: the FastAPI application
- `db`: the PostgreSQL database

PostgreSQL data is stored in a named Docker volume called `postgres_data`.

```yaml
services:
  web:
    build: .
    depends_on:
      - db
    ports:
      - "6161:8000"

  db:
    image: postgres:15-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    environment:
      - POSTGRES_USER=ekrem
      - POSTGRES_PASSWORD=ekrem6161
      - POSTGRES_DB=demo_db

volumes:
  postgres_data:
```

> Note: These credentials are for local demo purposes only. In real projects, database credentials should not be committed directly into source control.

## Run the Docker Compose Demo

From the project root:

```bash
cd compose-demo
```

Start the application and database:

```bash
docker compose up --build
```

Test the application:

```bash
curl http://localhost:6161/
```

Expected response:

```json
{
  "message": "FastAPI is running"
}
```

Test the health endpoint:

```bash
curl http://localhost:6161/health
```

Expected response:

```json
{
  "status": "ok"
}
```

Test the PostgreSQL connection:

```bash
curl http://localhost:6161/db-check
```

Expected response:

```json
{
  "db_status": "ok",
  "result": 1
}
```

Stop the environment:

```bash
docker compose down
```

Remove the PostgreSQL volume as well:

```bash
docker compose down -v
```

---

# Part 2 — Kubernetes Event API

The second part deploys a more complete FastAPI application and PostgreSQL database on Kubernetes.

This version is closer to a real deployment structure. It separates application configuration, database secrets, persistent storage, internal database networking, and external API exposure.

## Architecture

```text
Browser / curl
     |
     v
NodePort Service: k8s-event-api-service
     |
     v
FastAPI Deployment
  replicas: 3
     |
     v
ClusterIP Service: postgres-service
     |
     v
PostgreSQL Deployment
     |
     v
PersistentVolumeClaim
```

The FastAPI application talks to PostgreSQL through the Kubernetes service name:

```text
postgres-service:5432
```

This is defined in the ConfigMap:

```yaml
DB_HOST: postgres-service
DB_PORT: "5432"
```

## Files

```text
k8s-event-api/
├── app/main.py
├── Dockerfile
├── requirements.txt
└── k8s-yamls/
    ├── namespace.yaml
    ├── configmap.yaml
    ├── secrets.yaml
    ├── pvc.yaml
    ├── postgres-deployment.yaml
    ├── postgres-service.yaml
    ├── fastapi-deployment.yaml
    └── service.yaml
```

## Kubernetes Objects

| File | Kubernetes Object | Purpose |
|---|---|---|
| `namespace.yaml` | `Namespace` | Isolates the application resources in `k8s-event-api` namespace |
| `configmap.yaml` | `ConfigMap` | Stores non-sensitive app and database configuration |
| `secrets.yaml` | `Secret` | Stores the PostgreSQL password |
| `pvc.yaml` | `PersistentVolumeClaim` | Provides persistent storage for PostgreSQL data |
| `postgres-deployment.yaml` | `Deployment` | Runs the PostgreSQL container |
| `postgres-service.yaml` | `Service` | Exposes PostgreSQL inside the cluster with `ClusterIP` |
| `fastapi-deployment.yaml` | `Deployment` | Runs the FastAPI application with 3 replicas |
| `service.yaml` | `Service` | Exposes FastAPI outside the cluster with `NodePort` |

## FastAPI Application Features

The Kubernetes version includes a small event API.

### Application endpoints

| Endpoint | Method | Description |
|---|---:|---|
| `/` | GET | Returns app name, environment, version, and pod name |
| `/health` | GET | Basic health check |
| `/ready` | GET | Checks PostgreSQL connectivity with `SELECT 1` |
| `/info` | GET | Shows runtime configuration such as app name, environment, DB host, and pod name |
| `/events` | POST | Inserts a new event into PostgreSQL |
| `/events` | GET | Lists the latest events from PostgreSQL |
| `/stats` | GET | Returns basic event statistics |

### Database table

On startup, the application creates the `events` table if it does not exist:

```sql
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    source VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

This keeps the demo self-contained: once PostgreSQL is reachable, the API can initialize the required table automatically.

---

## Build the FastAPI Image

From the project root:

```bash
cd k8s-event-api
```

Build the Docker image:

```bash
docker build -t fastapi-event-api:latest .
```

The Kubernetes deployment uses:

```yaml
image: fastapi-event-api:latest
imagePullPolicy: Never
```

This means Kubernetes expects the image to already exist locally on the node.

### If you use Docker Desktop Kubernetes

Building the image normally is usually enough:

```bash
docker build -t fastapi-event-api:latest .
```

### If you use Minikube

Build the image inside the Minikube Docker environment:

```bash
eval $(minikube docker-env)
docker build -t fastapi-event-api:latest .
```

---

## Deploy to Kubernetes

Apply the manifests in a safe order.

```bash
kubectl apply -f k8s-yamls/namespace.yaml
kubectl apply -f k8s-yamls/configmap.yaml
kubectl apply -f k8s-yamls/secrets.yaml
kubectl apply -f k8s-yamls/pvc.yaml
kubectl apply -f k8s-yamls/postgres-deployment.yaml
kubectl apply -f k8s-yamls/postgres-service.yaml
kubectl apply -f k8s-yamls/fastapi-deployment.yaml
kubectl apply -f k8s-yamls/service.yaml
```

Or apply the whole folder:

```bash
kubectl apply -f k8s-yamls/
```

Check the resources:

```bash
kubectl get all -n k8s-event-api
```

Check the pods:

```bash
kubectl get pods -n k8s-event-api
```

Expected result:

```text
postgres-...     Running
fast-api-...     Running
fast-api-...     Running
fast-api-...     Running
```

Check the services:

```bash
kubectl get svc -n k8s-event-api
```

Expected services:

```text
postgres-service          ClusterIP
k8s-event-api-service     NodePort
```

---

## Test the Kubernetes Deployment

The FastAPI service is exposed with a NodePort on port `30080`.

```bash
curl http://localhost:30080/
```

Expected response example:

```json
{
  "message": "Kubernetes Event API is running",
  "app_name": "eventa-api",
  "environment": "dev",
  "version": "1.0.1",
  "pod": "fast-api-xxxxxxxxxx-xxxxx"
}
```

Check application health:

```bash
curl http://localhost:30080/health
```

Expected response example:

```json
{
  "status": "ok",
  "pod": "fast-api-xxxxxxxxxx-xxxxx"
}
```

Check database readiness:

```bash
curl http://localhost:30080/ready
```

Expected response example:

```json
{
  "status": "ready",
  "db_check": 1,
  "db_host": "postgres-service",
  "pod": "fast-api-xxxxxxxxxx-xxxxx"
}
```

If NodePort access does not work in your local Kubernetes environment, use port-forwarding:

```bash
kubectl port-forward -n k8s-event-api service/k8s-event-api-service 8080:80
```

Then test with:

```bash
curl http://localhost:8080/ready
```

---

## Create and Read Events

Create a new event:

```bash
curl -X POST http://localhost:30080/events \
  -H "Content-Type: application/json" \
  -d '{
    "source": "web-app",
    "event_type": "page_view",
    "payload": "{\"page\": \"home\"}"
  }'
```

Example response:

```json
{
  "id": 1,
  "source": "web-app",
  "event_type": "page_view",
  "payload": "{\"page\": \"home\"}",
  "created_at": "2026-01-01T12:00:00"
}
```

List events:

```bash
curl http://localhost:30080/events
```

Limit the result size:

```bash
curl "http://localhost:30080/events?limit=5"
```

Get event statistics:

```bash
curl http://localhost:30080/stats
```

Example response:

```json
{
  "stats": {
    "total_events": 1,
    "distinct_sources": 1,
    "distinct_event_types": 1
  },
  "pod": "fast-api-xxxxxxxxxx-xxxxx"
}
```

---

## Useful Kubernetes Commands

View application logs:

```bash
kubectl logs -n k8s-event-api deployment/fast-api
```

View PostgreSQL logs:

```bash
kubectl logs -n k8s-event-api deployment/postgres
```

Describe the FastAPI deployment:

```bash
kubectl describe deployment fast-api -n k8s-event-api
```

Describe the PostgreSQL deployment:

```bash
kubectl describe deployment postgres -n k8s-event-api
```

Enter one of the FastAPI pods:

```bash
kubectl exec -it deployment/fast-api -n k8s-event-api -- sh
```

Enter the PostgreSQL pod:

```bash
kubectl exec -it deployment/postgres -n k8s-event-api -- sh
```

Check the PostgreSQL service DNS from inside the FastAPI pod:

```bash
kubectl exec -it deployment/fast-api -n k8s-event-api -- sh
```

Inside the container:

```bash
python -c "import socket; print(socket.gethostbyname('postgres-service'))"
```

---

## Cleanup

Delete the Kubernetes resources:

```bash
kubectl delete namespace k8s-event-api
```

This removes the namespace and all resources inside it.

For the Docker Compose demo:

```bash
cd compose-demo
docker compose down -v
```

---

## Notes and Improvements

This project is intentionally simple enough to run locally, but it demonstrates patterns that are also used in real platform work.

Possible improvements:

- Add Kubernetes readiness and liveness probes to the FastAPI deployment
- Add PostgreSQL readiness checks
- Replace demo secrets with a real secret management solution
- Add CI/CD pipeline for image build and deployment
- Add database migrations with Alembic
- Add structured logging
- Add Helm chart or Kustomize overlays
- Add resource requests and limits for PostgreSQL
- Add Ingress instead of NodePort for a more production-like setup

---

## Summary

This repository shows the same application idea in two stages:

1. **Docker Compose stage**: FastAPI and PostgreSQL run locally as containers. This is useful for development and quick testing.
2. **Kubernetes stage**: FastAPI and PostgreSQL run as Kubernetes workloads. Configuration is separated into ConfigMaps and Secrets, PostgreSQL uses persistent storage, the database is exposed internally with ClusterIP, and the API is exposed externally with NodePort.

The project demonstrates a basic but practical deployment flow for backend and data-platform-style services.
