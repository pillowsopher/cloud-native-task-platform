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
  requirements-dev.txt      Test-only dependencies (pytest, httpx)
  pytest.ini                 pythonpath = . so `src` imports resolve
  tests/conftest.py           Swaps in SQLite before any src import, plus
                          the autouse table-reset and TestClient fixtures
  tests/test_monitors.py      healthz + full CRUD + validation-failure tests
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

      **Follow-up:** the k3s install/join process described above was
      done by hand over SSH - deliberately, to actually understand what
      k3s bootstrap involves before automating it (see the Phase 8 note
      below for the reasoning). It's now automated via Terraform
      `user_data` on both instances, run automatically on first boot:
      - The **server** needs a join token; instead of letting k3s
        generate a random one and having the agent fetch it after the
        fact, both instances are given the *same* fixed token up front,
        via a `random_password` resource (state-only, never in a
        tracked file) passed through `K3S_TOKEN`. This sidesteps the
        "agent needs to read something the server generated" problem
        entirely.
      - The **agent** needs the server's address, which Terraform
        provides directly (`aws_instance.k3s_server.private_ip`) - this
        also makes Terraform create the server first, since the agent's
        `user_data` now depends on that value.
      - The agent doesn't need to *wait* for the server to finish
        booting first: k3s's own agent already retries with backoff
        until the server responds (observed directly while debugging
        the original manual join), so both instances can boot
        simultaneously without any extra ordering logic.
      - Applying this change **replaces** both EC2 instances (`user_data`
        only ever runs on first boot, so changing it can't take effect
        any other way) - a deliberate rebuild to prove the automation
        actually reproduces a working cluster from nothing, not just a
        side effect to route around.
- [x] **Phase 7 — Lambda/serverless**: SQS-triggered notification path,
      in a separate Terraform state (`terraform/serverless/`) from the
      VPC/EC2 infra - logically distinct comparison path, not an
      extension of the container architecture. `worker`'s
      `send_notification` publishes to SQS (queue name only via a
      ConfigMap, never the full URL - that has the account ID baked
      in; resolved at runtime via `get_queue_url`) → triggers
      `lambda/notifications/handler.py` → writes to DynamoDB. Includes
      a dead-letter queue (`maxReceiveCount = 3`) after directly
      hitting the "one malformed message retries forever" problem
      while testing. Verified end-to-end by hand: sent a message
      straight to SQS, watched it show up in DynamoDB. The worker-side
      wiring itself hasn't been verified live yet (EC2 instances were
      torn down after Phase 6.5 to save cost) - next time the cluster
      is recreated, redeploy and confirm a real monitor going `down`
      produces a DynamoDB record.
- [x] **API test suite (pytest)**: also not tied to a numbered infra phase —
      needed before/during Phase 8, since a CI pipeline with an empty test
      stage isn't much of one. Uses FastAPI's `TestClient` against a
      SQLite database (swapped in via `DATABASE_URL` before any `src`
      import happens, so the app never touches real Postgres), with an
      `autouse` fixture that drops/recreates tables before every test for
      isolation. `pytest.ini` sets `pythonpath = .` so `src` imports
      resolve without installing the package. 10 tests covering `/healthz`,
      full monitor CRUD (create/list/get/update/delete, including 404s for
      an unknown ID), and a validation-failure case (missing required
      field → 422).
- [x] **Phase 8 — GitLab CI/CD**: pipeline lives in `.gitlab-ci.yml`, hosted
      on a separate GitLab mirror of this repo (GitHub stays the primary/
      backup remote — GitLab was added specifically for its free CI/CD
      minutes). Runs on push to `main` only:
  - **`lint`** — `ruff` against `services/api` and `services/worker`.
  - **`test`** — the `pytest` suite for `services/api`.
  - **`build_api` / `build_worker`** (parallel, both in the `build` stage) —
    build each image, tag it with the commit SHA (not `:latest`, for real
    traceability/rollback), push to ECR.
  - **`deploy`** — renders `k8s/*.yaml` with the real account ID and image
    tag substituted in, hands them off to `k3s-server` via S3 (SSM Run
    Command can execute shell commands but can't copy files, so S3 is the
    file hand-off point), then triggers `scripts/remote-deploy.sh` on the
    server via SSM to `kubectl apply` them and refresh the
    `ecr-registry-credentials` Secret.

      All AWS access is via GitLab's OIDC identity token exchanged for
      temporary credentials (`aws_iam_openid_connect_provider` +
      `aws_iam_role.gitlab_ci` in `terraform/main.tf`, scoped by condition
      to this exact project + `main` branch) — no long-lived AWS keys
      stored in GitLab. Deploy reaches `k3s-server` over SSM rather than
      SSH specifically because the security group's SSH rule is locked to
      `my_ip`, which GitLab's shared runners aren't. The instance-side
      commands (`kubectl apply`, the Secret refresh) run under the
      instance's own `ec2_ecr` IAM role via IMDS, not the CI job's
      credentials. A kubelet ECR credential-provider plugin would still be
      a more correct long-term fix than refreshing a Secret at all, but is
      out of scope for this pass.

      Verified end-to-end: a real push through `lint`/`test`/`build`/
      `deploy` went green, with `kubectl` on `k3s-server` showing the
      deployment running the freshly-built commit-SHA-tagged image.
      Getting there surfaced several real bugs, worth remembering: Alpine's
      `apk`-packaged `aws-cli` has a broken `pyexpat`/`expat` ABI on this
      image (switched CI jobs to `debian:12-slim` + `apt`), `s3 sync`
      needs `s3:ListBucket`/`s3:DeleteObject` in addition to `PutObject`/
      `GetObject` (bucket-level vs. object-level ARNs are separate IAM
      grants), `kubectl create secret docker-registry` has no
      `--docker-password-stdin` flag (unlike `docker login` - the password
      has to be a literal `--docker-password=` argument), and copying
      `k8s/*.yaml` unfiltered picked up `01-secret.example.yaml` and
      silently overwrote the real Secret with its placeholder password.
- [~] **Phase 9 — Monitoring**: skipped, deliberately. While verifying
      Phase 8 above, `k3s-server` was directly observed thrashing under
      real memory pressure (t3.micro's 1GB RAM, ~100Mi available, ~700Mi
      of the 1GB swap file in use, a control-plane query taking 7m47s) just
      running the existing workload (Postgres, Redis, 2x api, worker, beat,
      Traefik). Adding Prometheus + Grafana on top of that would make an
      already-tight node worse, not better - this isn't a hypothetical
      concern, it's the actual ceiling this project hit. Revisiting this
      would mean trimming the existing footprint first (e.g. `api` back to
      1 replica, since HPA can't act on 2 without metrics-server anyway),
      not just adding more to the same box.

## Current infra state: torn down

As of the last session, **all AWS infrastructure has been destroyed** -
`terraform/bootstrap/`, `terraform/main.tf`, and `terraform/serverless/` were
all `terraform destroy`'d. This is a personal learning project with no one
depending on its uptime, so there's no reason to keep paying free-tier hours
(or holding a t3.micro that's already near its resource ceiling, see Phase 9
above) for a cluster nobody's using. Everything above is still fully defined
as code and reproducible from scratch:

```powershell
cd terraform/bootstrap
terraform init
terraform apply

cd ..
terraform init -backend-config=backend.hcl
terraform apply

cd serverless
terraform init -backend-config=backend.hcl
terraform apply
```

(`bootstrap` must go first - it creates the S3/DynamoDB backend the other
two depend on. `serverless` must go after `main.tf` - it cross-references
the `ec2_ecr` IAM role via a `data` source, which fails to even plan if that
role doesn't exist yet.) After `main.tf`, you'd still need to redo the
Phase 6.5/8 app deploy (or just re-run the GitLab pipeline against `main`)
to get the actual application running again, and manually re-apply
`k8s/02-secret.yaml` since it's gitignored and never touched by CI.

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

## Known issues / environment workarounds

None of these are conceptual problems with the project — they're quirks of
this specific Windows/Docker Desktop machine, documented so future-me (or
anyone else) doesn't waste time rediscovering them:

- **Docker Desktop's image store is separate from its Kubernetes node's
  containerd**, unless "Use containerd for pulling and storing images" is
  enabled — and enabling it breaks this machine's Kubernetes cluster from
  starting at all. Workaround: `scripts/k8s-load-image.ps1` loads a locally
  built image directly into the node's containerd via `nsenter` + `ctr`,
  bypassing `docker build`'s separate store entirely. Local-only, gitignored.
- **`docker login` fails with a 400 Bad Request** against ECR on this Docker
  Desktop version (client-side bug — the credentials themselves are valid,
  confirmed via a raw `curl` Basic-auth request). The official
  `amazon-ecr-credential-helper` also fails separately ("credentials not
  found in native keychain", a Windows-specific bug). Workaround:
  `scripts/ecr-login.ps1` writes the base64 auth entry directly into
  Docker's config, same as a working `docker login` would.
- **PowerShell mangles `-backend-config=path`-style flags** passed to
  native executables (Terraform, in our case) — wrap the whole flag in
  quotes: `terraform init "-backend-config=backend.hcl"`.
- **Windows PowerShell 5.1's `-Encoding utf8` writes a BOM**, which Docker's
  Go-based JSON parser can't handle. Any script writing `~/.docker/config.json`
  needs `[System.Text.UTF8Encoding]::new($false)` instead (see
  `scripts/ecr-login.ps1`).
- **`t3.micro`'s 1GB RAM isn't enough for k3s's control plane alone** —
  the server would become unresponsive (API server hangs mid-TLS-handshake,
  `"container runtime is down"` in the logs) without a swap file. Handled
  automatically now via Terraform `user_data` on both instances, but worth
  knowing why that swap file exists if you ever wonder.

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
