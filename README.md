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
- [x] **Phase 5 — AWS fundamentals**: created a personal IAM Identity
      Center user (SSO, no long-lived access keys) with a break-glass IAM
      admin user as backup; built a VPC by hand (public subnet, internet
      gateway, route table, security group); launched EC2 instances into
      it and confirmed SSH access. These EC2 instances were for learning
      only and have been terminated — Terraform provisions the real
      k3s instances as code in Phase 6.
- [x] **Phase 6 — Terraform**: `terraform/bootstrap/` creates the remote
      state backend (S3 bucket + DynamoDB lock table) with local state,
      since it can't depend on the backend it's creating. `terraform/`
      (separate config, `backend "s3"` pointed at that bucket/table)
      recreates Phase 5's VPC/subnet/IGW/route table/security group
      (previously built by hand), plus both EC2 instances - verified
      with a real SSH login. `my_ip` is a variable read from a gitignored
      `terraform.tfvars`, kept out of committed code.
- [x] **Phase 6.5 — Deploy to the real k3s cluster**: installed k3s on
      both Terraform-provisioned EC2 instances and joined them (a swap
      file was needed on `k3s-server` - `t3.micro`'s 1GB RAM wasn't
      enough for the control plane alone). Added ECR repos + an IAM
      role/instance profile so the instances can pull images, and a
      k8s `imagePullSecrets` entry (manually refreshed, ~12h token
      lifetime - see `scripts/ecr-login.ps1` for the same problem on
      the push side) since a proper kubelet credential-provider plugin
      was out of scope for this pass. Switched the Ingress to
      `traefik` (k3s's built-in default) instead of the `nginx` used
      for local testing. Verified end-to-end through the real Ingress:
      created a monitor, watched it flip to `down`. The manifests now
      target the real cluster only - local Docker Desktop testing
      (Phase 4) served its purpose and isn't being kept in sync
      further. Metrics-server was never installed on this cluster, so
      the HPA objects exist but can't compute utilization yet.
- [ ] **Phase 7 — Lambda/serverless**: SQS-triggered notification path.
- [ ] **API test suite (pytest)**: also not tied to a numbered infra phase —
      needed before/during Phase 8, since a CI pipeline with an empty test
      stage isn't much of one.
- [ ] **Phase 8 — GitLab CI/CD**: automated lint/test/build/deploy pipeline.
- [ ] **Phase 9 — Monitoring**: Prometheus + Grafana deployed, *and* the
      API instrumented with its own `/metrics` endpoint (`prometheus-client`)
      — without this there's nothing app-specific for Prometheus to scrape.

## Local-only files (gitignored, recreate these yourself)

A few files are required to actually run this project but are deliberately
not committed. To reproduce a working setup from scratch:

- **`k8s/02-secret.yaml`** — copy `k8s/01-secret.example.yaml` to
  `k8s/02-secret.yaml` and fill in real values for `POSTGRES_PASSWORD` and
  `DATABASE_URL` (must use the same password in both places — see the
  Phase 4 debugging story in git history for what happens if they drift).
- **AWS SSO profile** — run `aws configure sso` and name the profile
  `uptime-monitor` (this exact name is referenced throughout `terraform/`
  and by any AWS CLI commands used in this project). Requires an IAM
  Identity Center permission set already assigned to your AWS account —
  see Phase 5 in Progress above for how that was set up.
- **EC2 key pair** — create one in the AWS Console named
  `uptime-monitor-key` (must match `key_name` in `terraform/main.tf`),
  download the `.pem`, and keep it somewhere local (referenced by full
  path when SSHing, e.g. `ssh -i "C:\path\to\uptime-monitor-key.pem"
  ubuntu@<instance-ip>`).
- **`terraform/terraform.tfvars`** — create with your own public IP
  (used to scope the security group's SSH rule to just you):
  ```hcl
  my_ip = "YOUR_PUBLIC_IP/32"
  ```
- **`terraform/backend.hcl`** — `terraform/main.tf` uses a deliberately
  empty `backend "s3" {}` block (backend config can't reference variables
  or data sources, so hardcoding real values there would mean committing
  your AWS account ID). The actual values are supplied at `init` time from
  this gitignored file instead:
  ```hcl
  bucket         = "uptime-monitor-terraform-state-<your-account-id>"
  key            = "uptime-monitor/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "uptime-monitor-terraform-lock"
  encrypt        = true
  profile        = "uptime-monitor"
  ```
- **Terraform state** — apply the bootstrap config first (creates the S3
  bucket + DynamoDB table other Terraform state lives in, using local
  state since it can't depend on a backend it's creating), then the main
  config, passing the backend file explicitly:
  ```powershell
  cd terraform/bootstrap
  terraform init
  terraform apply

  cd ..
  terraform init -backend-config=backend.hcl
  terraform apply
  ```

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
