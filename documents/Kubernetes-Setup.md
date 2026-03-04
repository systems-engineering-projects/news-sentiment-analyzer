# Kubernetes Setup (Docker Desktop)

This guide walks you through getting Kubernetes up and deploying the News Sentiment Comparison API using **Docker Desktop** as the cluster.

---

## Part 1: Prerequisites

### 1.1 Install Docker Desktop

- Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/) for your OS.
- Ensure Docker Desktop is running (Engine running in the status bar).

### 1.2 Install kubectl

You need the `kubectl` CLI to talk to the cluster.

**Check if already installed:**

```bash
kubectl version --client
```

If you see a client version, you're set. If you get "command not found":

- **macOS (Homebrew):** `brew install kubectl`
- **Windows (Chocolatey):** `choco install kubernetes-cli`
- **Other:** See [Install kubectl](https://kubernetes.io/docs/tasks/tools/)

---

## Part 2: Enable Kubernetes in Docker Desktop

1. Open **Docker Desktop**.
2. Go to **Settings** (gear icon) → **Kubernetes**.
3. Check **Enable Kubernetes**.
4. Click **Apply & Restart** and wait until Kubernetes shows as **Running** (cluster **Active**, 1 node).
5. Optional: Confirm in the left sidebar under **Kubernetes** that the cluster is **Active** and shows Kubernetes version (e.g. v1.34.x).

---

## Part 3: Fix kubectl Configuration (if needed)

If you run `kubectl cluster-info` or `kubectl get nodes` and see:

```text
The connection to the server localhost:8080 was refused
```

then kubectl is **not** using Docker Desktop's cluster (it's falling back to the old default). Fix it as follows.

### 3.1 Check what kubectl is using

```bash
# Is KUBECONFIG set? (empty = use default ~/.kube/config)
echo $KUBECONFIG

# Does the default config exist?
ls -la ~/.kube/config

# What's in it?
cat ~/.kube/config
```

- If `~/.kube/config` is **missing or empty**, Docker Desktop hasn't written its config yet.
- If `KUBECONFIG` is set to another file that doesn't have the Docker Desktop cluster, kubectl will try the wrong server (e.g. localhost:8080).

### 3.2 Ensure Docker Desktop wrote the config

1. **Quit Docker Desktop** completely (Docker menu → Quit).
2. **Start Docker Desktop** again and wait until it's fully up.
3. Open **Settings → Kubernetes** and ensure **Enable Kubernetes** is on; wait until it shows **Kubernetes running**.
4. Check again:

   ```bash
   ls -la ~/.kube/config
   cat ~/.kube/config
   ```

   You should see a cluster with a server URL like `https://kubernetes.docker.internal:6443` (not `http://localhost:8080`).

### 3.3 Unset a wrong KUBECONFIG

If `echo $KUBECONFIG` points to a file that doesn't contain Docker Desktop's cluster:

```bash
unset KUBECONFIG
```

Then kubectl will use `~/.kube/config`. Open a **new terminal** and verify (see Part 4).

---

## Part 4: Verify kubectl Is Configured

Run these from **any folder** (directory doesn't matter for these commands):

```bash
# Should print a context name (e.g. docker-desktop)
kubectl config current-context

# Should show Kubernetes control plane URL (not localhost:8080)
kubectl cluster-info

# Should list one node, status Ready
kubectl get nodes
```

Optional quick test:

```bash
kubectl run nginx --image nginx
kubectl get pods
kubectl delete pod nginx
```

If all of the above succeed, kubectl is configured and you can proceed to deployment.

---

## Part 5: Build the API Image (Local / Docker Desktop)

Docker Desktop's Kubernetes can use images built on the same machine without pushing to a registry.

From the **project root** (`news-sentiment-comparison/`):

```bash
cd /path/to/news-sentiment-comparison

# Build the image (use a simple name for local use)
docker build -t news-sentiment-api:latest .
```

Optional: if you prefer to push to a registry (e.g. Docker Hub), use your registry and push:

```bash
docker build -t your-registry/news-sentiment-api:latest .
docker push your-registry/news-sentiment-api:latest
```

Then in the steps below, use `your-registry/news-sentiment-api:latest` and keep `imagePullPolicy: Always` in the manifests.

---

## Part 6: Update Manifests for Your Image

### 6.1 Using a local image (no registry)

Edit these files under `k8s/` and set the image name to what you built, and allow using the local image:

- **`k8s/api-deployment.yaml`**  
  - Set `image` to `news-sentiment-api:latest` (or whatever you used in `docker build -t ...`).  
  - Set `imagePullPolicy: IfNotPresent` (or `Never`) so the cluster uses the local image.

- **`k8s/collector-cronjob.yaml`**  
  - Same `image` and `imagePullPolicy` as above.

### 6.2 Using a registry image

- In **`k8s/api-deployment.yaml`** and **`k8s/collector-cronjob.yaml`**, set `image` to e.g. `your-registry/news-sentiment-api:latest` and keep `imagePullPolicy: Always`.

---

## Part 7: Create the Namespace and Secrets

All `kubectl apply` and `kubectl create` commands below assume you are in the project root or use paths relative to it (e.g. `k8s/namespace.yaml`).

### 7.1 Create the namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

### 7.2 Create secrets (recommended: kubectl, not a file)

Replace the placeholder values with your real API keys and cron secret:

```bash
kubectl create secret generic news-sentiment-secrets \
  --namespace=news-sentiment \
  --from-literal=NEWS_API_KEY=your-newsapi-key \
  --from-literal=GROQ_API_KEY=your-groq-key \
  --from-literal=OPENAI_API_KEY=your-openai-key \
  --from-literal=CRON_SECRET_KEY=your-cron-secret
```

Do not commit real secrets to git. Alternatively you can edit `k8s/secrets.yaml` with real values and run `kubectl apply -f k8s/secrets.yaml`, but using `kubectl create secret` is safer.

---

## Part 8: Update ConfigMap (optional)

Edit `k8s/configmap.yaml` if you need to change:

- **CORS_ORIGINS** – your frontend URL (default: `https://sentimentlens.netlify.app`).
- **MONGODB_URI** – leave as `mongodb://mongodb-service:27017/news_sentiment` when using the in-cluster MongoDB from the manifests.

---

## Part 9: Deploy to Kubernetes

Run these in order from the project root.

```bash
# 1. ConfigMap
kubectl apply -f k8s/configmap.yaml

# 2. Secrets (only if you used secrets.yaml file; otherwise skip, you already created them)
# kubectl apply -f k8s/secrets.yaml

# 3. MongoDB
kubectl apply -f k8s/mongodb-statefulset.yaml

# 4. Wait for MongoDB to be ready
kubectl wait --for=condition=ready pod -l app=mongodb -n news-sentiment --timeout=300s

# 5. API
kubectl apply -f k8s/api-deployment.yaml

# 6. Collector CronJob
kubectl apply -f k8s/collector-cronjob.yaml

# 7. Optional: Ingress (requires an ingress controller in the cluster)
# kubectl apply -f k8s/ingress.yaml

# 8. Optional: Horizontal Pod Autoscaler (requires metrics-server)
# kubectl apply -f k8s/hpa.yaml
```

---

## Part 10: Verify Deployment

```bash
# All resources in the namespace
kubectl get all -n news-sentiment

# Pod status (wait until Running)
kubectl get pods -n news-sentiment

# API service (LoadBalancer may stay pending on Docker Desktop; use port-forward instead)
kubectl get svc news-sentiment-api-service -n news-sentiment

# Logs
kubectl logs -f deployment/news-sentiment-api -n news-sentiment
kubectl logs -f statefulset/mongodb -n news-sentiment
```

---

## Part 11: Access the API

On Docker Desktop, the LoadBalancer service often never gets an external IP. Use **port-forward** to reach the API from your machine:

```bash
kubectl port-forward -n news-sentiment deployment/news-sentiment-api 8000:8000
```

Leave this running. In another terminal (or browser):

```bash
curl http://localhost:8000/api/v1/health
curl http://localhost:8000/api/v1/today
```

Or open `http://localhost:8000/api/v1/health` in a browser.

To trigger collection manually (with port-forward active):

```bash
curl -X POST http://localhost:8000/api/v1/collect \
  -H "X-Cron-Secret: your-cron-secret-key"
```

---

## Summary Checklist (Docker option)

| Step | Action |
|------|--------|
| 1 | Install Docker Desktop and kubectl |
| 2 | Enable Kubernetes in Docker Desktop; wait until Active |
| 3 | If kubectl hits localhost:8080, fix kubeconfig (unset KUBECONFIG, restart Docker, check ~/.kube/config) |
| 4 | Verify: `kubectl config current-context`, `kubectl cluster-info`, `kubectl get nodes` |
| 5 | Build image: `docker build -t news-sentiment-api:latest .` (from project root) |
| 6 | Update `k8s/api-deployment.yaml` and `k8s/collector-cronjob.yaml` (image name and imagePullPolicy) |
| 7 | Create namespace and secrets: `kubectl apply -f k8s/namespace.yaml`, then `kubectl create secret generic ...` |
| 8 | Optionally edit `k8s/configmap.yaml` (CORS, etc.) |
| 9 | Deploy: configmap → mongodb → wait → api → collector-cronjob |
| 10 | Verify: `kubectl get all -n news-sentiment`, `kubectl get pods -n news-sentiment` |
| 11 | Access: `kubectl port-forward -n news-sentiment deployment/news-sentiment-api 8000:8000`, then `curl http://localhost:8000/api/v1/health` |

---

## Observability (Prometheus and Grafana)

The API exposes a **Prometheus metrics** endpoint at **GET /metrics** (request count and latency by path). You can scrape it with the **go-monitor** Prometheus stack and view dashboards in Grafana.

1. **Scrape from go-monitor:** When the API is reachable on the host (e.g. K8s LoadBalancer on port 80 or port-forward on 8000), run the **go-monitor** project (`docker-compose up` from the `go-monitor` directory). Its Prometheus is configured to scrape the News Sentiment API at `host.docker.internal:80` (or adjust the target in `go-monitor/prometheus/prometheus.yml` if the API is on a different host/port, e.g. `host.docker.internal:8000` for port-forward).

2. **Grafana dashboard:** The go-monitor stack includes a pre-provisioned dashboard **"News Sentiment API Dashboard"** (request rate, latency p95, error rate). Open Grafana at http://localhost:3000 (default login admin/admin) and select that dashboard when both the API and go-monitor are running.

---

## Troubleshooting: No fetch for today

After switching to Kubernetes, the daily "fetch" (headline collection) only runs when **the cluster is running** and the **CronJob** has fired.

**Why you might not see today's data**

1. **CronJob runs at 10:00 AM UTC** (`k8s/collector-cronjob.yaml`: `schedule: "0 10 * * *"`). If your cluster (e.g. Docker Desktop) is off or suspended at that time, the job does not run.
2. **CronJob not deployed** – The collector CronJob must be applied: `kubectl apply -f k8s/collector-cronjob.yaml`.
3. **Job failed** – Image pull, missing secrets, or MongoDB unreachable can cause the job pod to fail.

**Verify (run with cluster and kubectl context set)**

Run each command on its own line (avoid pasting the whole block so `-n news-sentiment` doesn't break):

```bash
# Is the CronJob present?
kubectl get cronjob -n news-sentiment

# When did it last run? (look at LAST SCHEDULE and ACTIVE)
kubectl get cronjob news-sentiment-collector -n news-sentiment

# Recent jobs and their status
kubectl get jobs -n news-sentiment

# Logs from the most recent collector job (if a job ran)
kubectl logs -n news-sentiment -l app=news-sentiment-collector --tail=100
```

If you paste the block and see `error: flag needs an argument: 'n' in -n`, the shell split a line: run `kubectl get cronjob news-sentiment-collector -n news-sentiment` as a single line.

**Backfill today (manual run)**

With the API reachable (e.g. port-forward):

```bash
curl -X POST http://localhost:8000/api/v1/collect \
  -H "X-Cron-Secret: your-cron-secret-key"
```

Or run the collector script locally (with same env as API: `MONGODB_URI`, `NEWS_API_KEY`, etc.):

```bash
python scripts/run_collector.py
```

---

## Troubleshooting: Backend has today's data but frontend doesn't show it

If the API or DB has a comparison for today but the UI does not, check the following.

1. **Which API is the frontend calling?**
   - **Dev server** (`npm run dev`): The frontend uses the Vite proxy: requests to `/api` go to `http://localhost:8000`. Ensure the API is reachable (e.g. `kubectl port-forward -n news-sentiment deployment/news-sentiment-api 8000:8000`). The frontend runs on the port in `vite.config.ts` (e.g. 3000).
   - **Built app or different origin:** The app uses `VITE_API_URL` if set. If you're opening a build or another origin, set `VITE_API_URL` to the API base (e.g. `http://localhost:8000/api/v1` when using port-forward). Otherwise the frontend may be hitting a different backend (e.g. Render) that uses a different DB and doesn't have today's data.

2. **CORS**
   - If the frontend runs on a different origin than the API (e.g. `http://localhost:3000` or `http://localhost:5173` and the API is on `http://localhost:8000`), the API must allow that origin. The K8s ConfigMap has `CORS_ORIGINS` (default in repo: Netlify only). For local UI, add your frontend origin:
     - Edit `k8s/configmap.yaml`: set `CORS_ORIGINS` to e.g. `"https://sentimentlens.netlify.app,http://localhost:3000,http://localhost:5173"`.
     - Re-apply: `kubectl apply -f k8s/configmap.yaml`, then restart the API deployment so it picks up the new config (e.g. `kubectl rollout restart deployment/news-sentiment-api -n news-sentiment`).

3. **Refetch**
   - The app loads `/today` only on initial load. Do a **hard refresh** (or reopen the tab) so it calls `/today` again.

4. **Verify in the browser**
   - Open DevTools → Network, reload the page, find the request to `/today` (or `/api/v1/today`). Check the response: 200 with JSON (data) vs 404 vs CORS error. That shows whether the frontend is talking to the right API and what it’s getting.

---

## See also

- Full Kubernetes reference: [k8s/README.md](../k8s/README.md)
- Docker and Compose: [DOCKER.md](DOCKER.md)
