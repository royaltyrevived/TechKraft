# TechKraft Senior Infrastructure Engineer Assignment
**Candidate:** [Your Name]
[cite_start]**Total Time Allotted:** 150 Minutes [cite: 3]
[cite_start]**Total Time Spent:** ~140 Minutes [cite: 271]

## 1. Infrastructure Analysis (Part 1)
[cite_start]I reviewed the provided Terraform configuration and identified several critical gaps preventing it from being production-ready[cite: 36, 129].

### [cite_start]Security Issues [cite: 130]
* [cite_start]**Hardcoded Credentials:** The RDS instance uses a plaintext password (`changeme123`)[cite: 112]. I recommend moving this to **AWS Secrets Manager**.
* [cite_start]**Overly Permissive Ingress:** Ports 22 and 80 are open to `0.0.0.0/0`[cite: 82, 91]. SSH should be restricted to a specific VPN/Jump Box CIDR.
* [cite_start]**Public RDS Placement:** The database is reachable via a public security group [cite: 113] [cite_start]and lacks private subnet isolation[cite: 19].
* [cite_start]**Attack Surface:** All instances have `map_public_ip_on_launch = true`[cite: 56], exposing them directly to the internet.
* [cite_start]**Missing Encryption:** S3 and RDS do not have server-side encryption (SSE) enabled[cite: 102, 121].
* [cite_start]**Data Loss Risk:** `deletion_protection` is set to `false` and `backup_retention_period` is `0` [cite: 116-117, 120].

### [cite_start]Architectural Problems [cite: 131]
* [cite_start]**Single Point of Failure (SPOF):** The RDS instance is not configured for Multi-AZ[cite: 102].
* [cite_start]**Manual Scaling:** Instances are created with `count` [cite: 58] instead of an **Auto Scaling Group (ASG)**.
* [cite_start]**Missing Load Balancer:** There is no ALB to distribute traffic across the backend EC2 instances[cite: 14].
* [cite_start]**Hardcoded AZs:** Availability zones are manually defined in a list [cite: 55] rather than dynamically fetched using a data source.
* [cite_start]**State Management:** The provider block lacks a remote backend (S3/DynamoDB) for `terraform.tfstate`[cite: 38].

---

## 2. Linux System Administration (Part 2)
### [cite_start]Troubleshooting `10.0.1.50` [cite: 135-141]
To diagnose the unresponsive server, I would execute the following steps in order:
1. [cite_start]**Verify Connectivity:** `ping 10.0.1.50` or `nc -zv 10.0.1.50 22` to check if the network layer is reachable[cite: 137].
2. [cite_start]**Check SSH Service:** Use `systemctl status ssh` or `netstat -tulpn | grep :22` once logged in via console[cite: 138].
3. [cite_start]**Identify Blockers:** If SSH is running but unreachable, I would check **Security Groups**, **NACLs**, or host-level `iptables`[cite: 139].
4. [cite_start]**Resource Audit:** Run `top`, `htop`, and `df -h` to check for CPU/Memory spikes or 100% disk utilization[cite: 140].
5. [cite_start]**Log Analysis:** Examine `journalctl -xe` or `/var/log/syslog` for kernel panics or service crashes[cite: 141].

### [cite_start]Multi-stage Dockerfile [cite: 143-144]
[cite_start]The Dockerfile implements a builder pattern to keep the production image slim and secure, running as a non-root user with an integrated health check[cite: 144].

---

## 3. Network Architecture Design (Part 5)
### [cite_start]Redundant DNS Solution [cite: 187-190]
[cite_start]To resolve the SPOF of a single Unbound EC2 instance [cite: 16-17], I propose a migration to **AWS Route 53**:

* [cite_start]**Primary Mechanism:** Use Route 53 as a managed DNS service (100% Availability SLA)[cite: 189].
* [cite_start]**Latency Optimization:** Implement **Latency-Based Routing** targeting `ap-south-1` (Mumbai) to ensure sub-100ms latency for Nepal-based users[cite: 189, 239].
* [cite_start]**Health Checks:** Configure Route 53 Health Checks to trigger a failover to a static "Maintenance" page hosted on S3 if backend targets fail [cite: 189-190].
* [cite_start]**Cost:** Estimated at ~$1.00/month (Managed Zone + Health Check), significantly cheaper than running an EC2 instance[cite: 190].

---

## 4. CI/CD Pipeline Review (Part 6)
### [cite_start]Identified Weaknesses [cite: 210]
* [cite_start]**No Approval Gate:** Deploys are triggered automatically on any push to `main`[cite: 197, 209].
* [cite_start]**Security Risk:** No automated SAST/Secret scanning for hardcoded credentials[cite: 213].
* [cite_start]**Rollback Risk:** The use of `rsync` does not support versioned artifacts or automated rollbacks[cite: 209, 216].

### [cite_start]Proposed Workflow [cite: 211-217]
[cite_start]`Lint/SAST` -> `Unit Tests` -> `Build Docker Image` -> `Deploy to Staging` -> **`Manual Approval Gate`** -> `Deploy to Prod (Blue/Green)`[cite: 217].

---

**Next Steps:**
I have implemented the code for `ec2_monitor.py` (Part 3) and `analyze_nginx_logs.sh` (Part 4) in their respective folders. Would you like me to walk through the logic of the **Nginx log parser** or the **Python AWS API integration** next?
