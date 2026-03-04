# Deploy to AWS (EKS + ALB)

This guide walks you through deploying the News Sentiment API to **Amazon EKS** and exposing it with an **Application Load Balancer (ALB)** so the API is live on the internet. Uses your existing Kubernetes manifests plus an AWS-specific Ingress.

---

## Prerequisites

- **AWS account** (new accounts get 750 hours/month of one ALB free for 12 months)
- **AWS CLI** installed and configured (`aws configure`)
- **kubectl** installed
- **eksctl** installed ([Install eksctl](https://eksctl.io/installation/))
- **Docker** (for building and pushing the image to ECR)

---

## Step 1: Create an EKS cluster

Choose a region (e.g. `us-east-1`) and create a small cluster:

```bash
eksctl create cluster \
  --name news-sentiment \
  --region us-east-1 \
  --nodegroup-name standard \
  --node-type t3.small \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3
```

This takes 15–20 minutes. When it finishes, `kubectl` will already be pointed at the new cluster.

**Verify:**

```bash
kubectl get nodes
```

---

## Step 2: Install the AWS Load Balancer Controller

The controller creates an ALB when you apply an Ingress with `ingressClassName: alb`.

**Before installing:** The controller needs an IAM role (OIDC provider + policy + Kubernetes service account). Do that first using the official guide below.

1. **Create IAM policy and role** (one-time per cluster). Follow the official [Install AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/deploy/installation/) steps: set up the IAM role for the controller, then install the controller via Helm or apply the YAML.

2. **Quick install via Helm** (if you have Helm):

   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName=news-sentiment \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller
   ```

   You must create the IAM role and service account first (see [Installation guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/deploy/installation/)).

3. **Verify:** After a few minutes, the controller pod should be running:

   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

---

## Step 3: Create ECR repository and push the image

1. **Create the repository:**

   ```bash
   aws ecr create-repository --repository-name news-sentiment-api --region us-east-1
   ```

   Note the **repositoryUri** from the output (e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com/news-sentiment-api`).

2. **Authenticate Docker to ECR:**

   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
   ```

   Replace `123456789012` with your AWS account ID.

3. **Build and push the image** (from the project root):

   ```bash
   cd /path/to/news-sentiment-comparison
   docker build -t news-sentiment-api:latest .
   docker tag news-sentiment-api:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/news-sentiment-api:latest
   docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/news-sentiment-api:latest
   ```

   Replace the ECR URL with your repositoryUri.

---

## Step 4: Update manifests to use the ECR image

In **`k8s/api-deployment.yaml`** and **`k8s/collector-cronjob.yaml`**, set `image` to your ECR URL, for example:

```yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/news-sentiment-api:latest
imagePullPolicy: Always
```

Use your actual account ID and region in the URL.

---

## Step 5: Deploy to the cluster

From the project root:

```bash
# Namespace
kubectl apply -f k8s/namespace.yaml

# ConfigMap and Secrets (create secrets with your real keys)
kubectl apply -f k8s/configmap.yaml
kubectl create secret generic news-sentiment-secrets \
  --namespace=news-sentiment \
  --from-literal=NEWS_API_KEY=your-key \
  --from-literal=GROQ_API_KEY=your-key \
  --from-literal=OPENAI_API_KEY=your-key \
  --from-literal=CRON_SECRET_KEY=your-key

# MongoDB
kubectl apply -f k8s/mongodb-statefulset.yaml
kubectl wait --for=condition=ready pod -l app=mongodb -n news-sentiment --timeout=300s

# API and CronJob
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/collector-cronjob.yaml

# Optional: HPA
kubectl apply -f k8s/hpa.yaml
```

**Update ConfigMap for production:** In `k8s/configmap.yaml`, set `CORS_ORIGINS` to your frontend URL (e.g. `https://sentimentlens.netlify.app`) and `MONGODB_URI` if using Atlas. Re-apply: `kubectl apply -f k8s/configmap.yaml`.

---

## Step 6: Apply the AWS Ingress (create the ALB)

Use the **AWS-specific** Ingress (not the nginx one):

```bash
kubectl apply -f k8s/ingress-aws.yaml
```

After a few minutes, the AWS Load Balancer Controller will create an Application Load Balancer. Get its address:

```bash
kubectl get ingress -n news-sentiment -w
```

When **ADDRESS** is populated, note the hostname (e.g. `k8s-newsse-xxxxx-xxxxx.us-east-1.elb.amazonaws.com`).

**Test:**

```bash
curl http://<ALB_HOSTNAME>/api/v1/health
```

---

## Step 7: Point the frontend to the ALB

1. **CORS:** Ensure `k8s/configmap.yaml` has `CORS_ORIGINS` set to your Netlify URL, then:

   ```bash
   kubectl apply -f k8s/configmap.yaml
   kubectl rollout restart deployment/news-sentiment-api -n news-sentiment
   ```

2. **Netlify:** In Netlify → Site settings → Environment variables, set:

   - `VITE_API_URL` = `http://<ALB_HOSTNAME>/api/v1`

   Use the ALB hostname from Step 6. Redeploy the frontend so the new variable is used.

---

## Cost notes

- **EKS control plane:** ~\$0.10/hour (~\$73/month if the cluster runs 24/7).
- **ALB:** New AWS accounts get **750 hours/month** of one ALB free for 12 months; after that you pay per hour and LCU.
- **Worker nodes:** Depends on instance type (e.g. t3.small). To minimize cost, use `--nodes-min 1` and scale down when not demoing, or delete the cluster when not in use:

  ```bash
  eksctl delete cluster --name news-sentiment --region us-east-1
  ```

---

## Summary

| Step | Action |
|------|--------|
| 1 | Create EKS cluster with `eksctl` |
| 2 | Install AWS Load Balancer Controller (Helm + IAM) |
| 3 | Create ECR repo, build image, push to ECR |
| 4 | Update `api-deployment.yaml` and `collector-cronjob.yaml` image to ECR URL |
| 5 | Apply namespace, configmap, secrets, mongodb, api, cronjob (and optional HPA) |
| 6 | Apply `k8s/ingress-aws.yaml`; get ALB hostname from `kubectl get ingress` |
| 7 | Set CORS and Netlify `VITE_API_URL` to the ALB URL |

For local Kubernetes (Docker Desktop), see [Kubernetes-Setup.md](Kubernetes-Setup.md). For the full K8s reference, see [k8s/README.md](../k8s/README.md).
