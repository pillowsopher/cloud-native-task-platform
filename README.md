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
┌───────▼────────────────────────┐                    ┌────────────▼────────────┐
│  k3s cluster (EC2 t3.micro x2)  │                    │     Serverless path      │
│  ┌──────────┐   ┌────────────┐  │                    │      SQS → Lambda        │
│  │ api pod  │──▶│ worker pod │  │  monitor down ───▶  │      → DynamoDB          │
│  │(FastAPI) │   │  (Celery)  │  │  triggers SQS msg   │  (logs notification;     │
│  └────┬─────┘   └─────┬──────┘  │                    │   no SES/real email)     │
│       │                │         │                    └──────────────────────────┘
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
| Database | Postgres | Persists monitors via SQLAlchemy ORM |
| Serverless path | Lambda (Python), SQS-triggered + DynamoDB | Alternate notification dispatch, shows serverless vs. container tradeoffs. No API Gateway — event-triggered, not HTTP-triggered. Logs notifications rather than sending real email (no SES, deliberately, to stay free/simple) |
| Containerization | Docker (multi-stage builds) | api + worker images |
| Orchestration | k3s on EC2 (free tier) | Deployments, Services, Ingress, HPA |
| CI/CD | GitLab CI | lint/test → build → push to ECR → deploy to k3s + Lambda |
| IaC | Terraform | VPC, EC2, security groups, IAM, ECR, Lambda, DynamoDB, SQS |
| Observability | Prometheus + Grafana (in-cluster), CloudWatch (Lambda side) | Metrics/dashboards |

## Repo layout

```
docker-compose.yml        Postgres + Redis + api + worker + beat, wired
                          together for local dev
.env.example               Template for required secrets (copy to .env, gitignored)
services/api/             FastAPI app (source of truth, actively built)
  src/main.py              Route handlers + Pydantic request/response models
  src/database.py          SQLAlchemy engine/session setup, reads DATABASE_URL
  src/models.py             SQLAlchemy ORM model (Monitor -> monitors table)
  requirements.txt         Pinned dependencies (pip)
  Dockerfile                Multi-stage, non-root runtime user
  .dockerignore             Excludes venv/, __pycache__/, etc. from the
                          image build context
services/worker/          Celery worker + Beat scheduler (same image, two
                          different container commands)
  src/celery_app.py         Celery app instance, broker/backend config,
                          beat_schedule
  src/tasks.py               dispatch_due_checks (fan-out), check_monitor
                          (real HTTP check), send_notification
  src/database.py, models.py  Own copies, not shared with services/api/ —
                          each service is independently buildable/deployable
  requirements.txt, Dockerfile, .dockerignore  Same pattern as services/api/
reference/                 Original auto-generated Node.js/Express scaffold,
                          kept locally (gitignored, not pushed) as an
                          answer key while services/ is rebuilt from
                          scratch by hand
```

`reference/` is not deployed and not kept in sync with `services/` — it's a
snapshot of one possible finished shape, useful to compare against if stuck,
not the live implementation.

## Progress

- [x] **Phase 1 — API from scratch**: FastAPI app with full CRUD
      (`POST/GET/PATCH/DELETE /monitors`), Pydantic validation, in-memory
      storage.
- [x] **Phase 2 — Docker**: multi-stage `Dockerfile` for the API
      (build stage installs deps, runtime stage stays lean), `.dockerignore`,
      image builds/runs/serves traffic identically to the local dev server.
- [x] **Phase 3 — Docker Compose**: Postgres + Redis + api wired together
      (healthchecks gate startup order, named volume for persistence),
      monitors now stored via SQLAlchemy/Postgres instead of an in-memory
      list, secrets sourced from a gitignored `.env` instead of being
      hardcoded.
- [x] **Worker service — Celery + Celery Beat**: not tied to a numbered
      infra phase (it's app code, not infra), but needed before Phase 4.
      Beat dispatches a due-check tick every 15s; the worker performs real
      HTTP checks per monitor honoring its own `check_interval_seconds`,
      writes `status`/`last_checked_at` back to Postgres, and fires a
      notification only on a transition to `down` (not on every check
      while already down). Both `api` and `worker` run as a non-root user.
- [x] **Phase 4 — Kubernetes (k3s)**: Deployments, Services, ConfigMaps/
      Secrets for postgres/redis/api/worker/beat, `Ingress` routing to the
      api service via ingress-nginx, and `HorizontalPodAutoscaler`s for api
      (2-5 replicas) and worker (1-3 replicas) on CPU utilization, backed by
      metrics-server. `beat` stays a fixed single replica (no HPA) since
      more than one Celery Beat scheduler would double-dispatch tasks.
      Verified end-to-end on a local cluster: created a monitor through the
      Ingress, watched the worker check it and flip status to `down`.
- [ ] **Phase 5 — AWS fundamentals**: IAM, EC2, VPC/security groups.
- [ ] **Phase 6 — Terraform**: provision the EC2/k3s infra as code,
      including a remote state backend (S3 + DynamoDB lock table) —
      standard practice once more than one machine/person touches the
      infra, and a common interview topic.
- [ ] **Phase 7 — Lambda/serverless**: SQS-triggered notification path.
- [ ] **API test suite (pytest)**: also not tied to a numbered infra phase —
      needed before/during Phase 8, since a CI pipeline with an empty test
      stage isn't much of one.
- [ ] **Phase 8 — GitLab CI/CD**: automated lint/test/build/deploy pipeline.
- [ ] **Phase 9 — Monitoring**: Prometheus + Grafana deployed, *and* the
      API instrumented with its own `/metrics` endpoint (`prometheus-client`)
      — without this there's nothing app-specific for Prometheus to scrape.

## Running the full stack (current)

The API now requires a real Postgres connection (`DATABASE_URL` is required,
no silent fallback), so the supported way to run it is via Docker Compose,
which brings up Postgres + Redis + the API together:

```
copy .env.example .env
docker compose up --build
```

`.env` holds `POSTGRES_PASSWORD` and is gitignored — copy the example and
fill in a real value before first run.

```powershell
$body = @{ name = "my site"; url = "https://example.com" } | ConvertTo-Json
$created = Invoke-RestMethod -Uri http://localhost:3000/monitors -Method Post -ContentType "application/json" -Body $body
Invoke-RestMethod -Uri http://localhost:3000/monitors -Method Get
Invoke-RestMethod -Uri "http://localhost:3000/monitors/$($created.id)" -Method Get
```

Interactive API docs (auto-generated by FastAPI): http://localhost:3000/docs

Data persists in the `pgdata` named volume across restarts:
```
docker compose down     # stops containers, keeps data
docker compose up
```
Use `docker compose down -v` instead to also wipe the volume (fresh database).

To run the API directly on your machine (outside Docker) for faster
iteration, export `DATABASE_URL` yourself first (pointing at a Postgres
you're running some other way — e.g. `docker compose up postgres` to start
just the database):
```powershell
cd services\api
venv\Scripts\activate
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/uptime_monitor"
uvicorn src.main:app --reload --port 3000
```

## License

[MIT](LICENSE)
