# Cloud-Native Task Platform

A small task-management app deployed three different ways to demonstrate the
core DevOps stack: **Docker → Kubernetes (self-managed on EC2) → Serverless
(Lambda)**, wired together with **GitLab CI/CD** and **Terraform**.


## Architecture

```
                        ┌─────────────────────────┐
                        │        GitLab CI          │
                        │ lint → test → build → push │
                        │   → deploy (k3s + Lambda)  │
                        └───────────┬────────────────┘
                                    │
        ┌───────────────────────────┴───────────────────────────┐
        │                                                         │
┌───────▼────────────────────────┐                    ┌───────────▼───────────┐
│  k3s cluster (EC2 t3.micro x2)  │                    │   Serverless path      │
│  ┌──────────┐   ┌────────────┐  │                    │  API Gateway → Lambda  │
│  │ api pod  │──▶│ worker pod │  │   task created ───▶ │  → DynamoDB            │
│  │(Express) │   │ (BullMQ)   │  │   triggers SQS msg   │  → SES (sandbox)       │
│  └────┬─────┘   └─────┬──────┘  │                    └────────────────────────┘
│       │                │         │
│  ┌────▼─────┐   ┌──────▼─────┐  │
│  │ Postgres │   │   Redis    │  │
│  │ (StatefulSet)│ (Deployment)│  │
│  └──────────┘   └────────────┘  │
└──────────────────────────────────┘
         ▲
         │ Terraform provisions: VPC, EC2 instances, security groups,
         │ IAM roles, ECR repo, Lambda + DynamoDB + SQS
```

## Why k3s instead of EKS

EKS charges ~$0.10/hr for the control plane even on free tier — not actually
free. **k3s** (lightweight Kubernetes) running on two `t3.micro`/`t2.micro`
EC2 free-tier instances gives you a real cluster — Deployments, Services,
Ingress, ConfigMaps/Secrets, HPA — for $0.

## Components

| Layer | Tech | Purpose |
|---|---|---|
| API service | Node.js/Express | CRUD for tasks, publishes events |
| Worker service | Node.js + BullMQ | Consumes queue, sends notifications |
| Serverless path | Lambda + API Gateway + DynamoDB + SQS | Alternate notification dispatch, shows serverless vs. container tradeoffs |
| Containerization | Docker (multi-stage builds) | api + worker images |
| Orchestration | k3s on EC2 (free tier) | Deployments, Services, Ingress, HPA |
| CI/CD | GitLab CI | lint/test → build → push to ECR → deploy to k3s + Lambda |
| IaC | Terraform | VPC, EC2, security groups, IAM, ECR, Lambda, DynamoDB, SQS |
| Observability | Prometheus + Grafana (in-cluster), CloudWatch (Lambda side) | Metrics/dashboards |

## Repo layout

```
services/api/          Express API (Dockerfile + source)
services/worker/        Notification worker (Dockerfile + source)
lambda/notification-dispatcher/   Serverless alternative path
k8s/                    Kubernetes manifests (namespace, deployments, svc, ingress, hpa)
terraform/              IaC for AWS infra (EC2, VPC, IAM, ECR, Lambda, DynamoDB)
monitoring/             Prometheus/Grafana manifests
.gitlab-ci.yml          Pipeline: lint → test → build → push → deploy
docker-compose.yml      Local dev environment
```

## Local development

```bash
docker compose up --build
curl -X POST localhost:3000/tasks -H 'content-type: application/json' -d '{"title":"demo","notify_email":"you@example.com"}'
```

## Deployment path (high level)

1. `terraform apply` in `terraform/` — provisions VPC, 2x EC2 instances, IAM roles, ECR repo, Lambda + DynamoDB + SQS.
2. Install k3s on the EC2 instances (`terraform/scripts/install-k3s.sh` runs via user-data).
3. GitLab CI builds Docker images, pushes to ECR, runs `kubectl apply -f k8s/` and `sam deploy` for the Lambda path.
4. Ingress (Traefik, bundled with k3s) exposes the API on the EC2 public IP.

