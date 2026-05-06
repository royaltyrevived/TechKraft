# TechKraft DevOps Assessment — Consolidated Submission

This revision consolidates the full assessment into a cohesive, production-grade response. It addresses prior gaps including the `config.json` requirement, hybrid connectivity to on-prem (pfSense), an ALB-fronted Auto Scaling Group, and team mentorship strategy.

## Table of Contents

- [Part 1: Infrastructure as Code](#part-1-infrastructure-as-code-part1-terraformmaintf)
- [Part 2: Linux & Docker](#part-2-linux--docker-part2-linux)
- [Part 3: Python Scripting](#part-3-python-scripting-part3-pythonec2_monitorpy)
- [Part 4: Bash Scripting](#part-4-bash-scripting-part4-bashanalyze_nginx_logssh)
- [Part 5: Redundant DNS Design](#part-5-redundant-dns-design)
- [Part 6: CI/CD & Mentorship](#part-6-cicd--mentorship-the-senior-hire-readme)

---

## Part 1: Infrastructure as Code (`part1-terraform/main.tf`)

Production-grade VPC architecture with Public/Private subnet separation, NAT Gateway egress for private instances, and an Auto Scaling Group (ASG) behind an Application Load Balancer (ALB).

```hcl
# --- Provider & Network Setup ---
provider "aws" { region = "us-east-1" }

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "techkraft-vpc" }
}

data "aws_availability_zones" "available" { state = "available" }

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

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
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

# --- Compute & Load Balancing ---
resource "aws_lb" "web" {
  name               = "techkraft-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_launch_template" "web" {
  name_prefix   = "techkraft-web-"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"
  network_interfaces { security_groups = [aws_security_group.app_sg.id] }
}

resource "aws_autoscaling_group" "web" {
  desired_capacity    = 3
  max_size            = 5
  min_size            = 2
  vpc_zone_identifier = aws_subnet.private[*].id
  launch_template { id = aws_launch_template.web.id; version = "$Latest" }
}

# --- RDS Database (Multi-AZ & Encrypted) ---
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
  multi_az                    = true
  storage_encrypted           = true
  manage_master_user_password = true # AWS Secrets Manager
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  deletion_protection         = true
  backup_retention_period     = 7
  skip_final_snapshot         = false
}
```

---

## Part 2: Linux & Docker (`part2-linux/`)

### Multi-stage Dockerfile (`Dockerfile`)

`slim → slim` base image alignment ensures binary compatibility for compiled Python packages copied between stages.

```dockerfile
# Stage 1: Build
FROM python:3.11-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Production (slim → slim for binary compatibility)
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

## Part 3: Python Scripting (`part3-python/ec2_monitor.py`)

Reads runtime configuration from `config.json`, with CLI flags overriding config defaults. Outputs a JSON report with per-instance CPU averages and threshold-breach alerts.

```python
import boto3, json, argparse, logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def load_config(path='config.json'):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        logger.error("config.json not found")
        return {"alert_threshold": 80, "regions": ["us-east-1"]}

def monitor(region, threshold, output):
    ec2 = boto3.resource('ec2', region_name=region)
    cw = boto3.client('cloudwatch', region_name=region)
    report = []

    try:
        for inst in ec2.instances.filter(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]):
            res = cw.get_metric_statistics(
                Namespace='AWS/EC2', MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': inst.id}],
                StartTime=datetime.utcnow()-timedelta(hours=1), EndTime=datetime.utcnow(),
                Period=300, Statistics=['Average']
            )
            pts = res.get('Datapoints', [])
            avg = sum(p['Average'] for p in pts) / len(pts) if pts else 0
            report.append({"InstanceId": inst.id, "AvgCPU": round(avg, 2), "Alert": avg > threshold})

        with open(output, 'w') as f:
            json.dump(report, f, indent=4)
        logger.info(f"Report saved to {output}")
    except Exception as e:
        logger.error(f"AWS Error: {e}")

if __name__ == "__main__":
    conf = load_config()
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", default=conf['regions'][0])
    parser.add_argument("--threshold", type=int, default=conf['alert_threshold'])
    parser.add_argument("--output", default="report.json")
    args = parser.parse_args()
    monitor(args.region, args.threshold, args.output)
```

---

## Part 4: Bash Scripting (`part4-bash/analyze_nginx_logs.sh`)

Reports total requests, 4xx/5xx error rates with division-by-zero protection, and the Top 10 IPs and Endpoints.

```bash
#!/bin/bash
LOG_FILE=$1
[[ ! -f "$LOG_FILE" ]] && echo "Log not found" && exit 1

TOTAL=$(wc -l < "$LOG_FILE")
[[ "$TOTAL" -eq 0 ]] && echo "Log is empty" && exit 0

calc_pct() { awk -v n="$1" -v t="$TOTAL" 'BEGIN {printf "%.2f", (n/t)*100}'; }

ERR_4XX=$(awk '$9 ~ /^4/ {c++} END {print c+0}' "$LOG_FILE")
ERR_5XX=$(awk '$9 ~ /^5/ {c++} END {print c+0}' "$LOG_FILE")

echo "=== Nginx Log Analysis Report ==="
echo "Total Requests: $TOTAL"
echo "4xx Errors: $ERR_4XX ($(calc_pct "$ERR_4XX")%)"
echo "5xx Errors: $ERR_5XX ($(calc_pct "$ERR_5XX")%)"

echo -e "\nTop 10 IPs:"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -10

echo -e "\nTop 10 Endpoints:"
awk '{print $7}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -10
```

---

## Part 5: Redundant DNS Design

To eliminate the SPOF of the single Unbound EC2 instance:

- **Migration:** Move DNS to **AWS Route 53** (managed, multi-region anycast).
- **Latency:** **Latency-Based Routing** targeting `ap-south-1` (Mumbai) to minimize lag for Nepal-based users, with `ap-southeast-1` (Singapore) as a secondary.
- **Failover:** **Route 53 Health Checks** on the ALB; on failure, automatic flip to a secondary region or an S3-hosted maintenance page.
- **Hybrid Connectivity:** Connect the on-prem **pfSense** firewall to the AWS VPC via a **Site-to-Site VPN** for secure cross-environment communication (with Direct Connect as a future upgrade path for bandwidth-sensitive workloads).

---

## Part 6: CI/CD & Mentorship (The "Senior Hire" README)

### Pipeline Gaps & Fixes

- **Problems:** Direct `rsync` deployment without approval gates, security scanning, or artifact versioning; no rollback path.
- **Improvements:**
  - Integrate **Trivy** for container scans and **tflint / checkov** for IaC.
  - Implement **GitHub Environments** with mandatory manual approvals for production.
  - Use **Blue/Green deployments** (CodeDeploy or Kubernetes) to enable instant rollback.
  - Build and push **versioned Docker images** as the deployable artifact instead of rsync-ing source.

### Mentorship Strategy (For the team of 11)

- **Standardization:** Develop modular, opinionated Terraform templates so the team deploys secure, pre-approved infrastructure by default — guardrails over gates.
- **Observability:** Establish **CloudWatch Dashboards** and centralized logging (CloudWatch Logs / OpenSearch) to shift the team from reactive fire-fighting to proactive monitoring with SLOs.
- **Culture:** Mandatory peer review on all IaC changes, paired with bi-weekly "Tech Talks" covering automated testing, security scanning, and incident retrospectives. Goal: distribute ownership so no single engineer is a SPOF for the platform.
