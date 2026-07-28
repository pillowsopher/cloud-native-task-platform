FROM python:3.12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev libpq-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends libpq5 && rm -rf /var/lib/apt/lists/*

# Removed --user, to stop user from running as root
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# changing dir to /usr/local unstead of /root/.local
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY src ./src

RUN chown -R appuser:appuser /app

USER appuser

# ---- NOTE: There are no EXPOSE or CMD commands, since worker doesn't listen on Network port.
# ---- Only reaches out to Postgres and Redis ----