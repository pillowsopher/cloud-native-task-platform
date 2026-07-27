# ---- Build stage: install dependencies ----
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ---- Final stage: runtime only ----
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /root/.local /root/.local
COPY src ./src

ENV PATH=/root/.local/bin:$PATH

EXPOSE 3000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "3000"]
