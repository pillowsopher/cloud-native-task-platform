# Cloud-Native Uptime Monitor

A small uptime-monitoring app (submit URLs, get notified when they go down),
built from scratch as a hands-on way to learn the DevOps stack: **Docker →
Kubernetes (self-managed k3s on EC2) → Serverless (Lambda)**, wired together
with **GitLab CI/CD** and **Terraform**.

This repo is being built incrementally, one technology at a time, rather than
generated all at once — see [Progress](#progress) for what's actually done
vs. planned.

## Architecture (target — see Progress for current state)

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
│  │ api pod  │──▶│ worker pod │  │  monitor down ───▶  │  → DynamoDB            │
│  │(FastAPI) │   │  (Celery)  │  │  triggers SQS msg   │  → SES (sandbox)       │
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

## What it does

You submit a URL to watch (name, URL, check interval). A periodic background
job (Celery Beat) checks it on schedule and flips its status between
`up`/`down`; a status change to `down` triggers an email notification. The
same "something reacts to an event" idea is re-implemented a second way via
an AWS Lambda triggered by SQS, to compare the container-worker approach
against a serverless one.

## Why k3s instead of EKS

EKS charges ~$0.10/hr for the control plane even on free tier — not actually
free. **k3s** (lightweight Kubernetes) running on two `t3.micro`/`t2.micro`
EC2 free-tier instances gives you a real cluster — Deployments, Services,
Ingress, ConfigMaps/Secrets, HPA — for $0.

## Components

| Layer | Tech | Purpose |
|---|---|---|
| API service | Python/FastAPI | CRUD for monitors, validation via Pydantic |
| Worker service | Python + Celery + Redis | Periodic checks, sends notifications on status change |
| Database | Postgres | Persists monitors (replaces in-memory storage once wired up) |
| Serverless path | Lambda (Python) + API Gateway + DynamoDB + SQS | Alternate notification dispatch, shows serverless vs. container tradeoffs |
| Containerization | Docker (multi-stage builds) | api + worker images |
| Orchestration | k3s on EC2 (free tier) | Deployments, Services, Ingress, HPA |
| CI/CD | GitLab CI | lint/test → build → push to ECR → deploy to k3s + Lambda |
| IaC | Terraform | VPC, EC2, security groups, IAM, ECR, Lambda, DynamoDB, SQS |
| Observability | Prometheus + Grafana (in-cluster), CloudWatch (Lambda side) | Metrics/dashboards |

## Repo layout

```
services/api/           FastAPI app (source of truth, actively built)
reference/               Original auto-generated Node.js/Express scaffold,
                          kept as an answer key while services/ is rebuilt
                          from scratch by hand
```

`reference/` is not deployed and not kept in sync with `services/` — it's a
snapshot of one possible finished shape, useful to compare against if stuck,
not the live implementation.

## Progress

- [x] **Phase 1 — API from scratch**: FastAPI app with full CRUD
      (`POST/GET/PATCH/DELETE /monitors`), Pydantic validation, in-memory
      storage.
- [ ] **Phase 2 — Docker**: containerize the API.
- [ ] **Phase 3 — Docker Compose**: wire up Postgres + Redis locally,
      replace in-memory storage.
- [ ] **Phase 4 — Kubernetes (k3s)**: Deployments, Services, ConfigMaps/
      Secrets, Ingress, HPA.
- [ ] **Phase 5 — AWS fundamentals**: IAM, EC2, VPC/security groups.
- [ ] **Phase 6 — Terraform**: provision the EC2/k3s infra as code.
- [ ] **Phase 7 — Lambda/serverless**: SQS-triggered notification path.
- [ ] **Phase 8 — GitLab CI/CD**: automated lint/test/build/deploy pipeline.
- [ ] **Phase 9 — Monitoring**: Prometheus + Grafana.

## Local development (current)

```powershell
cd services\api
venv\Scripts\activate
uvicorn src.main:app --reload --port 3000
```

Then, from another terminal:

```powershell
$body = @{ name = "my site"; url = "https://example.com" } | ConvertTo-Json
Invoke-RestMethod -Uri http://localhost:3000/monitors -Method Post -ContentType "application/json" -Body $body
Invoke-RestMethod -Uri http://localhost:3000/monitors -Method Get
```

Interactive API docs (auto-generated by FastAPI): http://localhost:3000/docs
