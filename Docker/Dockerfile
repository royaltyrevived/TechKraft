# Stage 1: Build
FROM python:3.11-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Production (Slim to Slim for binary compatibility)
FROM python:3.11-slim
RUN groupadd -r techkraft && useradd -r -g techkraft techuser
WORKDIR /app
COPY --from=builder /root/.local /home/techuser/.local
COPY app.py .
ENV PATH=/home/techuser/.local/bin:$PATH
USER techuser
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:5000/health || exit 1
CMD ["python", "app.py"]
