# TechKraft DevOps Assessment

This repository contains the solution for the TechKraft DevOps assessment, covering infrastructure refactoring, Linux/Docker hardening, automation scripting, DNS redundancy design, and CI/CD pipeline review.

## Table of Contents

- [Part 1: Infrastructure Analysis & Refactored IaC](#part-1-infrastructure-analysis--refactored-iac)
- [Part 2: Linux & Docker](#part-2-linux--docker)
- [Part 3: Python Scripting](#part-3-python-scripting)
- [Part 4: Bash Scripting](#part-4-bash-scripting)
- [Part 5: Redundant DNS Design](#part-5-redundant-dns-design)
- [Part 6: CI/CD Pipeline Review](#part-6-cicd-pipeline-review)

---

## Part 1: Infrastructure Analysis & Refactored IaC

### 1. Analysis

**Security Issues**
- Hardcoded RDS credentials.
- Overly permissive ingress (SSH/HTTP open to `0.0.0.0/0`).
- Public subnets only — no private tier for the database.
- Missing storage encryption.
- Missing deletion protection.
- No backup retention configured.

**Architectural Issues**
- RDS is a Single Point of Failure (no Multi-AZ).
- Manual EC2 scaling using `count` instead of an Auto Scaling Group.
- No Load Balancer for traffic distribution.
- Hardcoded Availability Zones.
- No remote state backend for Terraform.

### 2. Refactored Terraform (`part1-terraform/main.tf`)

The refactored code implements a Public/Private VPC architecture with a NAT Gateway so private instances can fetch updates while remaining unreachable from the internet.

```hcl
# --- VPC and Networking ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "techkraft-vpc" }
}

data "aws_availability_zones" "available" { state = "available" }

# Public Subnets (for ALB & NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

# Private Subnets (for App & DB)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# NAT Gateway for Private Subnet Internet Access
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}

# --- Security Groups (Least Privilege) ---
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;  to_port = 0;  protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Least Privilege
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# --- Database Refactor ---
resource "aws_db_subnet_group" "main" {
  name       = "techkraft-db-sn-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "mysql" {
  identifier                  = "techkraft-db"
  engine                      = "mysql"
  instance_class              = "db.t3.medium"
  allocated_storage           = 20
  db_subnet_group_name        = aws_db_subnet_group.main.name
  multi_az                    = true # Solves SPOF
  storage_encrypted           = true # Compliance fix
  manage_master_user_password = true # Secrets Manager integration
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  deletion_protection         = true
  backup_retention_period     = 7
  skip_final_snapshot         = false
}
```

---

## Part 2: Linux & Docker

### 1. Troubleshooting (`troubleshooting.md`)

Structured escalation for diagnosing host `10.0.1.50`:

1. **Network**: `ping -c 4 10.0.1.50` and `nc -zv 10.0.1.50 22`.
2. **Service**: Access via AWS Serial Console; run `systemctl status ssh` and `ss -tulpn | grep :22`.
3. **Access Issues**: Check Security Group ingress, host `/etc/hosts.deny`, or filesystem corruption preventing SSH key reads.
4. **Resources**: `htop` for CPU/RAM; `df -h` and `iostat` for disk/IO bottlenecks.
5. **Logs**: `journalctl -xe` and `tail -f /var/log/auth.log` for failed login attempts.

### 2. Multi-stage Dockerfile

**Fix:** Unified the base image to `python:3.11-slim` to ensure binary compatibility (avoiding `glibc` vs `musl` conflicts when copying compiled Python packages between stages).

```dockerfile
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim
RUN groupadd -r techkraft && useradd -r -g techkraft techuser
WORKDIR /app
COPY --from=builder /root/.local /home/techuser/.local
COPY app.py .
ENV PATH=/home/techuser/.local/bin:$PATH
USER techuser
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:5000/health || exit 1
CMD ["python", "app.py"]
```

---

## Part 3: Python Scripting (`ec2_monitor.py`)

Lists running EC2 instances, queries CloudWatch CPU metrics, and flags hosts breaching the configured threshold. Uses structured logging and explicit error handling.

```python
import boto3
import json
import argparse
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def get_instance_report(region: str, threshold: int):
    try:
        ec2 = boto3.resource('ec2', region_name=region)
        cw = boto3.client('cloudwatch', region_name=region)
        report = []

        instances = ec2.instances.filter(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )

        for inst in instances:
            name = next((t['Value'] for t in inst.tags if t['Key'] == 'Name'), 'Unnamed')

            response = cw.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': inst.id}],
                StartTime=datetime.utcnow() - timedelta(hours=1),
                EndTime=datetime.utcnow(),
                Period=300,
                Statistics=['Average', 'Minimum', 'Maximum']
            )

            points = response.get('Datapoints', [])
            if points:
                avg = sum(p['Average'] for p in points) / len(points)
                report.append({
                    "InstanceId": inst.id,
                    "Name": name,
                    "Type": inst.instance_type,
                    "AvgCPU": round(avg, 2),
                    "Alert": avg > threshold
                })
        return report
    except Exception as e:
        logger.error(f"Failed to fetch metrics: {e}")
        return []
```

---

## Part 4: Bash Scripting (`analyze_nginx_logs.sh`)

Robust nginx access log parser with division-by-zero protection and aligned output.

```bash
#!/bin/bash
LOG_FILE=$1
[[ ! -f "$LOG_FILE" ]] && echo "Log file not found" && exit 1

TOTAL=$(wc -l < "$LOG_FILE")
[[ "$TOTAL" -eq 0 ]] && echo "Log file is empty" && exit 0

calc_pct() {
  awk -v n="$1" -v t="$TOTAL" 'BEGIN { printf "%.2f", (n/t)*100 }'
}

ERR_4XX=$(awk '$9 ~ /^4/ {c++} END {print c+0}' "$LOG_FILE")
ERR_5XX=$(awk '$9 ~ /^5/ {c++} END {print c+0}' "$LOG_FILE")

echo "=== Nginx Log Analysis Report ==="
echo "Total Requests: $TOTAL"
echo "4xx Errors: $ERR_4XX ($(calc_pct "$ERR_4XX")%)"
echo "5xx Errors: $ERR_5XX ($(calc_pct "$ERR_5XX")%)"
echo -e "\nTop 10 IPs:"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -10
```

---

## Part 5: Redundant DNS Design

Replace the existing Unbound-on-EC2 SPOF with **AWS Route 53** as a managed, redundant resolver layer.

- **Routing Policy:** Latency-Based Routing targeting **ap-south-1 (Mumbai)** for Nepal-based users, with **ap-southeast-1 (Singapore)** as a secondary region.
- **Failover:** Route 53 Health Checks monitor the primary ALB. On failure, DNS flips to a static maintenance page on S3 or to the secondary region's ALB.
- **Cost Estimate:** ~$0.50/hosted zone + ~$0.50/health check ≈ **$1.00/month** baseline.
- **Migration Window:** 2–3 hours including cutover and validation.

---

## Part 6: CI/CD Pipeline Review

### 1. Problems Identified

- **No Approval Gate:** Deploys to production automatically on every push to `main`.
- **Security Risk:** No secret masking or scanning for hardcoded credentials.
- **No Artifact Versioning:** Uses `rsync` directly instead of building a versioned Docker image or package.
- **No Rollback Strategy:** If `rsync` fails or code is buggy, there is no automated way to revert.

### 2. Proposed Improvements

- **Security Scanning:** Integrate `Trivy` for container image scans and `tflint` / `checkov` for IaC.
- **Environment Promotion:** `main` branch deploys to Staging; tagging a release (e.g., `v1.0.0`) triggers Production.
- **Approval Gate:** Use GitHub Environments with "Required Reviewers" for Production.
- **Blue/Green Deployment:** Use AWS CodeDeploy or Kubernetes rolling/blue-green strategies for zero-downtime deploys and instant rollback.
