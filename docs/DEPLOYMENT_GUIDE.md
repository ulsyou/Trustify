# Trustify DevOps: Enterprise AWS Infrastructure & Deployment Guide

This document provides end-to-end instructions for **installation**, **provisioning**, **verification**, **CI/CD automation**, and **cleanup** of the Trustify containerized FastAPI and PostgreSQL infrastructure on AWS, simulated locally on **LocalStack Pro** using **`tflocal`** and **`awslocal`**.

---

## 1. Overview & Simulation Architecture

The infrastructure deploys a containerized FastAPI application with a dedicated PostgreSQL database following enterprise 3-tier cloud architecture principles.

```
                      INTERNET
                         │
                         ▼
             [ Internet Gateway (IGW) ]
                         │
        ┌────────────────┴────────────────┐
        │       Public Subnets (x2)       │
        │   ┌─────────────────────────┐   │
        │   │ Application Load Balancer│  │ (HTTP :80)
        │   └────────────┬────────────┘   │
        │                │                │
        │   [ NAT Gateway & Elastic IP ]  │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │     Private App Subnets (x2)    │
        │   ┌────────────▼────────────┐   │
        │   │  ECS Fargate Container  │   │ (:8000 FastAPI)
        │   └────────────┬────────────┘   │
        └────────────────┼────────────────┘
                         │ (TCP :5432)
        ┌────────────────┼────────────────┐
        │      Private DB Subnets (x2)    │
        │   ┌────────────▼────────────┐   │
        │   │  RDS PostgreSQL 16.1    │   │ (Isolated)
        │   └─────────────────────────┘   │
        └─────────────────────────────────┘
```

### 1.1 Key Architectural Parameters
- **Target Region:** `ap-southeast-2` (Sydney).
- **Workload High-Availability Tier:** 
  - **`dev` & `staging` are strictly Single-AZ:** `db_multi_az = false` (no standby RDS replica) and `nat_gateway_count = 1` (single NAT gateway) to minimize operational cost.
  - **`prod` is Multi-AZ:** `db_multi_az = true` and `nat_gateway_count = 2` (high-availability redundancy).
  - *(Note: Subnets exist across 2 AZs (`2a`, `2b`) solely because AWS hard-requires at least 2 AZs to instantiate an ALB and an RDS Subnet Group; subnets themselves incur no AWS charges).*
- **Naming Standard:** `${var.prefix}-${var.project}-${var.environment}-<resource>` (`tru-demo-dev-...`).

---

## 2. LocalStack Installation & Environment Setup

Follow these steps to set up your local AWS simulation environment from scratch.

### 2.1 System Prerequisites
Ensure the following tools are installed on your machine:
- **Docker Desktop** (running and healthy): [Download Docker](https://www.docker.com/products/docker-desktop/)
- **Python 3.10+** (with `pip`): [Download Python](https://www.python.org/downloads/)
- **Terraform CLI** (v1.5+): [Download Terraform](https://developer.hashicorp.com/terraform/install)
- **AWS CLI v2**: [Download AWS CLI](https://aws.amazon.com/cli/)

---

### 2.2 Install LocalStack CLI (`lstk`)
Install the official LocalStack CLI using your preferred package manager:

#### Windows (Winget or Scoop):
```powershell
# Using Winget
winget install LocalStack.LocalStack

# Or using Scoop
scoop bucket add localstack https://github.com/localstack/scoop-bucket.git
scoop install localstack
```

#### Via Python Pip (Alternative):
```powershell
pip install localstack
```

---

### 2.3 Install Automation Wrappers (`tflocal` & `awslocal`)
Install the Python CLI wrappers that automatically route Terraform and AWS CLI calls to the local emulator without requiring manual endpoint overrides:

```powershell
pip install awscli-local terraform-local
```

#### Add Python Scripts to Your PATH:
If running on Windows and `tflocal` or `awslocal` is not recognized, add the Python Scripts directory to your PowerShell session:
```powershell
# Current session:
$env:PATH += ";$env:APPDATA\Python\Python314\Scripts"

# Permanently for User (PowerShell):
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:APPDATA\Python\Python314\Scripts",
    "User"
)
```

---

### 2.4 Start & Authenticate LocalStack

1. **Start the emulator:**
   ```powershell
   lstk start
   ```

2. **Select Emulator Type:**
   When prompted, choose `AWS`:
   ```
   Which emulator would you like to use? AWS
   ✔︎ AWS emulator selected.
   ✔︎ Pulled localstack/localstack-pro:latest
   ✔︎ LocalStack is running (containerId: a2272fc4baee)
   • Endpoint: localhost.localstack.cloud:4566
   ```

3. **Verify STS caller identity:**
   ```powershell
   awslocal sts get-caller-identity
   ```
   *Expected Output:*
   ```json
   {
       "UserId": "AKIAIOSFODNN7EXAMPLE",
       "Account": "000000000000",
       "Arn": "arn:aws:iam::000000000000:root"
   }
   ```

4. **Verify Health Endpoint:**
   ```powershell
   curl http://localhost:4566/_localstack/health
   ```

---

## 3. Step-by-Step Deployment Instructions

In an enterprise GitOps workflow, **infrastructure is never provisioned manually from developer workstations for shared environments**. All production-grade deployments are driven by automated **GitHub Actions CI/CD Pipelines** with auditable plan reviews, OIDC authentication, and automated smoke testing.

Local command-line operations (`tflocal`) are reserved strictly for rapid developer sandbox prototyping.

---

### 3.1 Primary Deployment Method: Automated CI/CD Pipelines (GitOps)

#### Method A: Continuous Delivery on Merge (Standard Flow)
Every commit merged into the `main` branch automatically triggers the deployment pipeline:
1. **Pull Request Validation ([`ci.yml`](../.github/workflows/ci.yml)):**
   - Automatically runs `terraform fmt -check`, `terraform validate`, and **Checkov** security scans.
   - Generates an immutable plan and posts the plan diff as a sticky comment directly on the PR for peer review.
2. **Dev Deployment:** Automatically deploys the full stack to `dev`.
3. **Automated Smoke Testing:** Runs an automated curl health check against `http://<alb-endpoint>/health` to verify container reachability and database connectivity.
4. **Staging Promotion:** Automatically deploys to `staging` upon successful dev verification.
5. **Production Approval Gate:** Pauses execution and requires manual review and sign-off from designated DevOps Leads before applying to `prod`.

---

#### Method B: Manual Workflow Dispatch (GitHub Actions UI / CLI)
For out-of-band updates, emergency hotfixes, or targeted changes, use GitHub's manual workflow dispatch:

##### 1. Via GitHub Web UI:
1. Navigate to **Actions** &rarr; **IaC Deployment Pipeline**.
2. Click **Run workflow**.
3. Select your target branch (e.g., `main`).
4. Choose the **Target environment** (`dev`, `staging`, or `prod`).
5. *(Optional)* Specify a **Target resource or module** (e.g. `module.ecs` or `module.rds`). Leave blank to deploy the full environment.
6. Click **Run workflow**.

##### 2. Via GitHub CLI (`gh`):
```bash
# Deploy full Dev environment
gh workflow run deploy.yml -f environment=dev

# Deploy full Staging environment
gh workflow run deploy.yml -f environment=staging

# Surgical Hotfix: Deploy only the ECS service in Dev without touching network or database
gh workflow run deploy.yml -f environment=dev -f target="module.ecs"

# Multi-target Hotfix: Deploy ECS and ALB
gh workflow run deploy.yml -f environment=dev -f target="module.ecs module.alb"
```

---

### 3.2 Secondary Method: Local Developer Sandbox (`tflocal` Prototyping)

Use this method **only** when developing new modules offline or prototyping locally in LocalStack prior to pushing Git commits.

#### Step 1: Bootstrap Local Remote State Backend (`shared/backend`)
```powershell
# From project root:
cd iac/shared/backend

# Initialize backend stack
tflocal init

# Generate & review plan
tflocal plan -out=backend.tfplan

# Apply the reviewed plan
tflocal apply backend.tfplan
```

#### Step 2: Deploy Dev Environment Stack (`environments/dev`)
```powershell
# From project root:
cd iac/environments/dev

# Initialize modules
tflocal init

# Generate immutable execution plan
tflocal plan -out=dev.tfplan

# Apply reviewed plan
tflocal apply dev.tfplan
```

*(Optional) Layered local apply during module development:*
```powershell
# Apply network foundation first
tflocal apply -target=module.network

# Incrementally apply dependent layers
tflocal apply -target=module.security_groups
tflocal apply -target=module.alb
tflocal apply -target=module.rds
tflocal apply -target=module.ecr
tflocal apply -target=module.ecs
tflocal apply -target=module.monitoring
```

---

## 4. Live Simulation Results (Dev Environment Snapshot)

All resources below were verified deployed in LocalStack (`ap-southeast-2`):

### 4.1 Remote State & Lock
| Resource | Physical ID / Name | Notes |
| :--- | :--- | :--- |
| **S3 State Bucket** | `tru-demo-tfstate-apse2` | Versioning enabled, AES-256 encrypted |
| **DynamoDB Lock Table** | `tru-demo-tfstate-lock` | Primary key: `LockID` |

---

### 4.2 Network Layer (`aws_network`)
| Resource | Physical ID / Name | CIDR / Target |
| :--- | :--- | :--- |
| **VPC** | `vpc-27763900ad42f3aa7` (`tru-demo-dev-vpc`) | `10.10.0.0/16` |
| **Public Subnet 2a** | `subnet-a7effbcc550ddef31` (`tru-demo-dev-public-ap-southeast-2a`) | `10.10.0.0/20` |
| **Public Subnet 2b** | `subnet-d79b63817058b5595` (`tru-demo-dev-public-ap-southeast-2b`) | `10.10.16.0/20` |
| **Private App Subnet 2a** | `subnet-c38bcee9339d90bfa` (`tru-demo-dev-app-ap-southeast-2a`) | `10.10.32.0/20` |
| **Private App Subnet 2b** | `subnet-ed047f655e013b3e8` (`tru-demo-dev-app-ap-southeast-2b`) | `10.10.48.0/20` |
| **Private DB Subnet 2a** | `subnet-5e97a20ba4d45a502` (`tru-demo-dev-db-ap-southeast-2a`) | `10.10.64.0/20` |
| **Private DB Subnet 2b** | `subnet-98b41fd808f13497b` (`tru-demo-dev-db-ap-southeast-2b`) | `10.10.80.0/20` |
| **RDS Subnet Group** | `tru-demo-dev-db-subnet-group` | 2 DB Subnets |
| **Internet Gateway** | `igw-e51e6d26cc26f38ac` (`tru-demo-dev-igw`) | Attached to VPC |
| **NAT Gateway** | `nat-32260c237ca21352f` (`tru-demo-dev-nat-1`) | In Public Subnet 2a |
| **Elastic IP** | `eipalloc-13eff0e053b4665d8` (`tru-demo-dev-nat-eip-1`) | Attached to NAT |

---

### 4.3 Security Groups (`aws_security_groups`)
| Security Group | Physical ID / Name | Allowed Traffic (Least Privilege) |
| :--- | :--- | :--- |
| **ALB SG** | `sg-bf1f034921648c059` (`tru-demo-dev-alb-sg`) | Ingress: Port `80` from `0.0.0.0/0` |
| **App SG** | `sg-aefc5a8aa1e903a4f` (`tru-demo-dev-app-sg`) | Ingress: Port `8000` strictly from `sg-bf1f034921648c059` |
| **DB SG** | `sg-897427d6e7e811d39` (`tru-demo-dev-db-sg`) | Ingress: Port `5432` strictly from `sg-aefc5a8aa1e903a4f` |

---

### 4.4 Load Balancer (`aws_alb`)
| Resource | Physical ID / Name | Configuration |
| :--- | :--- | :--- |
| **ALB** | `arn:aws:elasticloadbalancing:ap-southeast-2:000000000000:loadbalancer/app/tru-demo-dev-alb/c813e24c381e44f1` | Public Application Load Balancer |
| **ALB DNS Name** | `tru-demo-dev-alb.elb.localhost.localstack.cloud` | Active HTTP endpoint |
| **Target Group** | `arn:aws:elasticloadbalancing:ap-southeast-2:000000000000:targetgroup/tru-demo-dev-tg/8ec3dbd704bf432b` | Port `8000`, Target: `ip`, Healthcheck: `/health` |

---

### 4.5 Container Registry & Compute (`aws_ecr`, `aws_ecs`)
| Resource | Physical ID / Name | Details |
| :--- | :--- | :--- |
| **ECR Repository** | `000000000000.dkr.ecr.ap-southeast-2.localhost.localstack.cloud:4566/tru-demo-dev-ecr` | Image scanning & lifecycle purge policy |
| **ECS Cluster** | `arn:aws:ecs:ap-southeast-2:000000000000:cluster/tru-demo-dev-cluster` | Fargate compute |
| **ECS Service** | `arn:aws:ecs:ap-southeast-2:000000000000:service/tru-demo-dev-cluster/tru-demo-dev-service` | Launch type: `FARGATE`, Desired count: 1 |
| **Task Definition** | `arn:aws:ecs:ap-southeast-2:000000000000:task-definition/tru-demo-dev-app:1` | 256 CPU, 512MB RAM, awsvpc mode |
| **Execution Role** | `arn:aws:iam::000000000000:role/tru-demo-dev-ecs-exec-role` | Image pull + CloudWatch + Secrets Manager |
| **Task Role** | `arn:aws:iam::000000000000:role/tru-demo-dev-ecs-task-role` | Application runtime role |
| **Log Group** | `/ecs/tru-demo-dev-app` | CloudWatch Logs (7-day retention) |

---

### 4.6 Database & Secrets Management (`aws_rds`)
| Resource | Physical ID / Name | Connection / Details |
| :--- | :--- | :--- |
| **RDS Instance** | `tru-demo-dev-pg` (`db-0B8D9B15`) | PostgreSQL 16.1 (`available`) |
| **RDS Endpoint** | `localhost.localstack.cloud:4510` | Isolated inside private subnets |
| **Secrets Manager** | `arn:aws:secretsmanager:ap-southeast-2:000000000000:secret:tru-demo-dev-db-credentials-AyTRME` | Keys: `host`, `port`, `username`, `password`, `dbname`, `database_url` |

---

### 4.7 Monitoring & Alerting (`aws_monitoring`)
| Resource | Physical Name / ARN | Metric / Trigger |
| :--- | :--- | :--- |
| **SNS Topic** | `arn:aws:sns:ap-southeast-2:000000000000:tru-demo-dev-alerts` | Alert delivery topic |
| **Subscription** | `devops@example.com` | Email notifications |
| **ALB 5xx Alarm** | `tru-demo-dev-alb-target-5xx` | Threshold: > 5 target 5xx errors / min |
| **ECS Memory Alarm**| `tru-demo-dev-ecs-memory-high` | Threshold: > 85% memory utilization |

---

## 5. Verification Commands (`awslocal`)

Run these commands in PowerShell to inspect live resources:

### 5.1 Inspect VPC & Subnets
```powershell
# List VPC
awslocal ec2 describe-vpcs --region ap-southeast-2 --filters "Name=tag:Name,Values=tru-demo-dev-vpc" --output table

# List Subnets
awslocal ec2 describe-subnets --region ap-southeast-2 --filters "Name=vpc-id,Values=vpc-27763900ad42f3aa7" --query "Subnets[*].{Name:Tags[?Key=='Name'].Value | [0],SubnetId:SubnetId,CidrBlock:CidrBlock,AZ:AvailabilityZone}" --output table
```

### 5.2 Inspect Gateways & Load Balancer
```powershell
# NAT Gateway
awslocal ec2 describe-nat-gateways --region ap-southeast-2 --filter "Name=vpc-id,Values=vpc-27763900ad42f3aa7" --output table

# ALB
awslocal elbv2 describe-load-balancers --region ap-southeast-2 --query "LoadBalancers[*].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}" --output table
```

### 5.3 Inspect Database & Secrets
```powershell
# RDS Database
awslocal rds describe-db-instances --region ap-southeast-2 --query "DBInstances[*].{Identifier:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port}" --output table

# Secrets Manager
awslocal secretsmanager list-secrets --region ap-southeast-2 --query "SecretList[*].{Name:Name,ARN:ARN}" --output table
```

### 5.4 Inspect ECS & CloudWatch Alarms
```powershell
# ECS Cluster & Services
awslocal ecs list-clusters --region ap-southeast-2
awslocal ecs list-services --cluster tru-demo-dev-cluster --region ap-southeast-2

# CloudWatch Alarms
awslocal cloudwatch describe-alarms --region ap-southeast-2 --query "MetricAlarms[*].{Name:AlarmName,Metric:MetricName,Threshold:Threshold}" --output table
```

---

## 6. Cleanup & Teardown Instructions

---

### 6.1 Primary Teardown Method: Automated Teardown Pipeline (`destroy.yml`)

In enterprise environments, infrastructure teardown is guarded by manual confirmation gates to prevent accidental outages.

#### 1. Via GitHub Web UI:
1. Navigate to **Actions** &rarr; **IaC Teardown Pipeline**.
2. Click **Run workflow**.
3. Select the **Target environment** (`dev`, `staging`, or `prod`).
4. *(Optional)* Specify a **Target resource or module** (e.g. `module.ecs`). Leave blank to destroy the full environment.
5. In the confirmation prompt, type **`DESTROY`** (case-sensitive safety check).
6. Click **Run workflow**.

#### 2. Via GitHub CLI (`gh`):
```bash
# Full environment destruction (Dev)
gh workflow run destroy.yml -f environment=dev -f confirm_destroy="DESTROY"

# Targeted subsystem destruction (e.g. ECS only)
gh workflow run destroy.yml -f environment=dev -f target="module.ecs" -f confirm_destroy="DESTROY"
```

---

### 6.2 Secondary Method: Local Sandbox Teardown (`tflocal`)

When cleaning up a local LocalStack experiment:

#### Step 1: Destroy Local Dev Stack
```powershell
# From project root:
cd iac/environments/dev

# Review destruction plan
tflocal plan -destroy -out=destroy.tfplan

# Apply destruction
tflocal apply destroy.tfplan
```

#### Step 2: Destroy Backend State (Optional)
```powershell
# From project root:
cd iac/shared/backend

tflocal destroy
```

#### Step 3: Stop LocalStack Emulator
```powershell
lstk stop
```

---

## 7. Enterprise IaC CI/CD Pipeline Architecture

In an enterprise DevOps workflow, manual command-line applies (`tflocal apply`) are strictly for local sandbox experimentation. All team-shared infrastructure changes flow through automated **GitOps CI/CD Pipelines** in `.github/workflows/`.

### 7.1 Pipeline Lifecycle

```
 Developer PR               GitHub Actions CI                Merge to Main               Production Promotion
┌─────────────┐            ┌──────────────────┐            ┌───────────────┐           ┌────────────────────┐
│ Code Change │ ─────────► │  1. Lint & Fmt   │ ─────────► │ Auto-Apply to │ ────────► │  Manual Approval   │
│ & Modules   │            │  2. Sec Scan     │            │      Dev      │           │    Gate for Prod   │
└─────────────┘            │  3. Plan on PR   │            └───────┬───────┘           └─────────┬──────────┘
                           └──────────────────┘                    │                             │
                                                                   ▼                             ▼
                                                           [ Smoke Tests ]               [ Prod Apply ]
                                                          (/health, /db-check)
```

### 7.2 GitHub Actions Workflows

1. **Application Delivery Pipeline ([`.github/workflows/application-deployment-pipeline.yml`](../.github/workflows/application-deployment-pipeline.yml)):**
   - **Quality Gate:** Automated linting with `flake8`, Dockerfile syntax validation, and module import tests.
   - **Progressive Delivery (AWS Cloud):** On merge to `main`, builds container and pushes to Amazon ECR, rolls out to **Dev** ECS Fargate &rarr; verifies health via ALB curl tests &rarr; rolls out to **Staging** &rarr; pauses at **Production** for manual DevOps approval.
   - **Manual Single-Environment Dispatch:** Allows targeting a specific environment (`dev`, `staging`, `prod`) on demand via GitHub Actions UI or `gh` CLI.

2. **Pull Request Quality Pipeline ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)):**
   - **Static Analysis:** Runs `terraform fmt -check`, `terraform validate`, and `tflint`.
   - **Security Scanning:** Runs `checkov` to detect misconfigurations and security flaws before merge.
   - **Plan Generation:** Executes `terraform plan` for the changed environment and posts the exact execution diff as a sticky markdown comment on the PR for team review.

3. **Infrastructure Delivery Pipeline ([`.github/workflows/iac-provision-pipeline.yml`](../.github/workflows/iac-provision-pipeline.yml)):**
   - **Automated Progressive Delivery:** On merge to `main`, automatically plans and deploys `dev`, runs automated health smoke tests, then progresses to `staging`, and holds before `prod` for manual approval.
   - **Manual Targeted Dispatch:** Allows team members to dispatch manual runs on specific environments.

4. **Infrastructure Teardown Pipeline ([`.github/workflows/iac-destroy-pipeline.yml`](../.github/workflows/iac-destroy-pipeline.yml)):**
   - **Protection Mechanism:** Enforces strict manual dispatch and requires typing `"DESTROY"` in `confirm_destroy` before running.
   - **Targeted Destruction:** Allows destroying an individual subsystem or the complete environment.

5. **Dynamic Targeting Design (Zero Pipeline Maintenance):**
   - Both `iac-provision-pipeline.yml` and `iac-destroy-pipeline.yml` avoid hardcoding module names in `type: choice` dropdowns.
   - Instead, they use a flexible string input (`type: string` with default `""`):
     - **Full Environment (Default):** Leaving `target` empty automatically plans and applies (or destroys) the whole environment declaratively.
     - **Break-Glass Hotfixes / Surgical Takedowns:** Engineers can input any valid Terraform resource address (e.g., `module.ecs`, `module.rds`, or multiple space-separated targets like `module.ecs module.alb`) directly into the workflow prompt.
     - **Result:** You will never need to update the CI/CD workflow YAML when new modules or resources are added to `iac/`!

6. **Zero-Secret Authentication:**
   - Authenticates to AWS via **GitHub OIDC (OpenID Connect)**. No long-lived AWS Access Keys are stored in GitHub Secrets.
