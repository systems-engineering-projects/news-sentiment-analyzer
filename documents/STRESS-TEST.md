# HPA Stress Test (Quick, Under 10 Minutes)

This guide walks you through a quick stress test so you can see the API pods scale up under load and scale back down when load stops. It uses the **Horizontal Pod Autoscaler (HPA)** and **metrics-server** in your Kubernetes cluster (e.g. Docker Desktop).

---

## Prerequisites

- The News Sentiment API is already deployed in Kubernetes (see [Kubernetes-Setup.md](Kubernetes-Setup.md) in this folder).
- `kubectl` is configured and pointing at your cluster.

---

## Step 1: Install metrics-server

The HPA needs **metrics-server** so it can read CPU/memory usage and decide when to scale.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Wait about a minute for metrics-server to be ready, then verify:

```bash
kubectl top pods -n news-sentiment
```

If you see CPU/memory for your pods, metrics-server is working.

**Docker Desktop note:** If `kubectl top pods` fails with TLS errors (e.g. "x509: certificate signed by unknown authority"), metrics-server may need to allow insecure TLS to the Kubelet. Patch the deployment:

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Then wait a minute and run `kubectl top pods -n news-sentiment` again.

---

## Step 2: Apply the HPA

The project includes an HPA that scales the API deployment between 2 and 10 replicas based on CPU (70%) and memory (80%):

```bash
kubectl apply -f k8s/hpa.yaml
```

Check that the HPA exists and shows current metrics (may take a short time):

```bash
kubectl get hpa -n news-sentiment
kubectl describe hpa news-sentiment-api-hpa -n news-sentiment
```

---

## Step 3: Run the load test

**Option A – In-cluster (no local install):** Run `hey` as a one-off pod inside the cluster. From the project root:

```bash
kubectl run -it --rm hey --image=williamyeh/hey --restart=Never -n news-sentiment -- \
  hey -z 90s -c 30 http://news-sentiment-api-service/api/v1/today
```

This sends load for **90 seconds** with **30 concurrent connections** to the API. Leave this terminal running until it finishes.

**Option B – From your host:** If the API is exposed on localhost (e.g. LoadBalancer on port 80):

```bash
# Install hey if needed: brew install hey
hey -z 90s -c 30 http://localhost/api/v1/today
```

---

## Step 4: Watch pods and HPA

Open **two other terminals** and run:

**Terminal 1 – Pod count:**

```bash
kubectl get pods -n news-sentiment -w
```

**Terminal 2 – HPA status:**

```bash
kubectl get hpa -n news-sentiment -w
```

During the 90-second load you should see:

- HPA **current replicas** and **target** increase (e.g. 2 → 4 → 6) as CPU/memory rise.
- New API pods (**news-sentiment-api-...**) appear and become **Running**.

After the load stops:

- HPA will scale down after its **scale-down stabilization** (e.g. 5 minutes in the current config).
- Pods will terminate until you’re back near **minReplicas** (2).

Press Ctrl+C in each watch terminal when you’re done.

---

## Summary

| Step | Command / action |
|------|-------------------|
| 1 | `kubectl apply -f .../components.yaml` (metrics-server); optionally patch with `--kubelet-insecure-tls` on Docker Desktop |
| 2 | `kubectl apply -f k8s/hpa.yaml` |
| 3 | Run `hey` (in-cluster or from host) for ~90s |
| 4 | `kubectl get pods -n news-sentiment -w` and `kubectl get hpa -n news-sentiment -w` |

**Optional script:** From the project root you can run:

```bash
./scripts/stress-test.sh
```

It checks metrics-server, applies the HPA, prints the watch commands, then runs the in-cluster load for 90 seconds. Open two other terminals and run the printed watch commands to see pods and HPA update.

For full Kubernetes setup and observability (Prometheus/Grafana), see [Kubernetes-Setup.md](Kubernetes-Setup.md) in this folder.
