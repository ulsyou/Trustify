# Trustify: Enterprise Cloud-Native Platform

[![Terraform](https://img.shields.io/badge/IaC-Terraform_1.9-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS_ap--southeast--2-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![LocalStack](https://img.shields.io/badge/Emulation-LocalStack_Pro-0052CC?logo=localstack&logoColor=white)](https://localstack.cloud/)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL_16.1-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

**Trustify** is an enterprise-grade cloud platform featuring a containerized FastAPI application with PostgreSQL persistence, orchestrated via modular Terraform Infrastructure as Code (IaC), tested locally on **LocalStack Pro**, and delivered through automated **GitHub Actions GitOps pipelines**.

---

## 🏛️ Architecture Overview

The platform implements a classic enterprise **3-tier VPC architecture** designed for high security, strict traffic isolation, and progressive deployment:

```
                      INTERNET
                         │
                         ▼
             [ Internet Gateway (IGW) ]
                         │
        ┌────────────────┴────────────────┐
        │       Public Subnets (x2)       │
        │   ┌─────────────────────────┐   │
        │   │ Application Load Balancer│  │ (Port :80 HTTP Ingress)
        │   └────────────┬────────────┘   │
        │                │                │
        │   [ NAT Gateway & Elastic IP ]  │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │     Private App Subnets (x2)    │
        │   ┌────────────▼────────────┐   │
        │   │  ECS Fargate Container  │   │ (Port :8000 FastAPI Service)
        │   └────────────┬────────────┘   │
        └────────────────┼────────────────┘
                         │ (Port :5432)
        ┌────────────────┼────────────────┐
        │      Private DB Subnets (x2)    │
        │   ┌────────────▼────────────┐   │
        │   │  RDS PostgreSQL 16.1    │   │ (Isolated Database Tier)
        │   └─────────────────────────┘   │
        └─────────────────────────────────┘
```

### Environment Tiers
| Environment | High Availability | NAT Gateways | RDS Deployment | Promotion Gate |
| :--- | :--- | :--- | :--- | :--- |
| **`dev`** | Single-AZ | 1 Gateway | Single Instance (`db_multi_az = false`) | Auto on merge to `main` |
| **`staging`** | Single-AZ | 1 Gateway | Single Instance (`db_multi_az = false`) | Auto after Dev smoke test |
| **`prod`** | **Multi-AZ** | 2 Gateways | Multi-AZ Standby (`db_multi_az = true`) | Manual Approval Required |

---

## 📁 Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml               # Format checks, linting, Checkov security scan & PR plan comments
│       ├── deploy.yml           # Automated progressive deployment + manual targeted dispatch
│       └── destroy.yml          # Guarded teardown pipeline with 'DESTROY' confirmation gate
├── app/
│   ├── compose-demo/            # Docker Compose local reference implementation
│   └── postgres-fastapi-.../    # Application container source code & requirements
├── docs/
│   └── DEPLOYMENT_GUIDE.md      # Comprehensive LocalStack, Terraform & CI/CD deployment guide
├── iac/
│   ├── environments/
│   │   ├── dev/                 # Dev environment stack (Single-AZ, 10.10.0.0/16)
│   │   ├── staging/             # Staging environment stack (Single-AZ, 10.20.0.0/16)
│   │   └── prod/                # Production environment stack (Multi-AZ, 10.30.0.0/16)
│   ├── modules/
│   │   ├── alb/                 # Application Load Balancer & Target Groups
│   │   ├── ecr/                 # Elastic Container Registry & lifecycle policies
│   │   ├── ecs/                 # ECS Fargate Cluster, Task Defs & Services
│   │   ├── monitoring/          # CloudWatch Alarms & SNS Alert Topics
│   │   ├── network/             # 3-Tier VPC, Subnets, Gateways & Route Tables
│   │   ├── rds/                 # PostgreSQL RDS & AWS Secrets Manager integration
│   │   └── security_groups/     # Chained least-privilege Security Groups
│   └── shared/
│       └── backend/             # Remote state S3 bucket & DynamoDB lock table bootstrap
└── README.md                    # Project landing page & index
```

---

## 🚀 Deployment Workflows

In enterprise operations, **all deployments are executed via GitOps CI/CD pipelines**; local terminal applies (`tflocal`) are reserved strictly for rapid offline prototyping.

### 1. Primary Workflow: GitOps CI/CD Pipelines
- **Automated Progressive Delivery ([`deploy.yml`](.github/workflows/deploy.yml)):**
  - Merging code into `main` automatically deploys **Dev**, runs automated ALB health checks (`/health`), promotes to **Staging**, and holds at **Production** for manual DevOps approval.
- **Pull Request Quality Gate ([`ci.yml`](.github/workflows/ci.yml)):**
  - Automatically runs `terraform fmt -check`, `terraform validate`, and **Checkov** security scans.
  - Generates immutable plan diffs and posts them as PR comments.
- **Guarded Teardown ([`destroy.yml`](.github/workflows/destroy.yml)):**
  - Enforces safety gates requiring typing `"DESTROY"` to prevent accidental data loss.
- **Manual & Targeted Dispatch:**
  - Deploy or destroy specific modules on demand using the GitHub Actions UI or GitHub CLI:
    ```bash
    # Deploy only ECS in Dev via pipeline
    gh workflow run deploy.yml -f environment=dev -f target="module.ecs"

    # Safely teardown Dev with confirmation
    gh workflow run destroy.yml -f environment=dev -f confirm_destroy="DESTROY"
    ```

---

### 2. Secondary Workflow: LocalStack Developer Sandbox
When prototyping new modules offline before creating a Git commit:
```powershell
# 1. Start LocalStack
lstk start

# 2. Bootstrap Remote State
cd iac/shared/backend
tflocal init && tflocal apply -out=backend.tfplan

# 3. Deploy Dev Stack
cd ../../environments/dev
tflocal init && tflocal apply -out=dev.tfplan

# 4. Inspect Live Resources
awslocal elbv2 describe-load-balancers --region ap-southeast-2 --output table
awslocal rds describe-db-instances --region ap-southeast-2 --output table
```

---

## 📚 Documentation Index

For complete step-by-step guides, live LocalStack resource IDs, CLI command cheat sheets, and cleanup procedures, refer to:

👉 **[Trustify Enterprise Deployment & Verification Guide](docs/DEPLOYMENT_GUIDE.md)**
