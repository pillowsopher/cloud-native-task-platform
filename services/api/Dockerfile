# ---- Build stage: install dependencies ----
FROM python:3.12-slim AS builder

# Adds gcc compiler for postgres and only install recommended packages
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev libpq-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ---- Final stage: runtime only ----
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends libpq5 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /root/.local /root/.local
COPY src ./src

ENV PATH=/root/.local/bin:$PATH

EXPOSE 3000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "3000"]
