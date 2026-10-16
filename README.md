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
│       ├── ci.yml                             # IaC format checks, validation, Checkov scan & PR plan comments
│       ├── iac-provision-pipeline.yml         # IaC progressive provisioning + manual targeted dispatch
│       ├── iac-destroy-pipeline.yml           # Guarded IaC teardown pipeline with 'DESTROY' confirmation gate
│       └── application-deployment-pipeline.yml# Application build, test, ECR push & ECS rolling deployment
├── app/
│   ├── compose-demo/                          # FastAPI demo with PostgreSQL connection & health endpoints
│   └── k8s-event-api/                         # Kubernetes event API reference implementation
├── docs/
│   └── DEPLOYMENT_GUIDE.md                    # Comprehensive LocalStack, Terraform & CI/CD deployment guide
├── iac/
│   ├── environments/
│   │   ├── dev/                               # Dev environment stack (Single-AZ, 10.10.0.0/16)
│   │   ├── staging/                           # Staging environment stack (Single-AZ, 10.20.0.0/16)
│   │   └── prod/                              # Production environment stack (Multi-AZ, 10.30.0.0/16)
│   ├── modules/
│   │   ├── alb/                               # Application Load Balancer & Target Groups
│   │   ├── ecr/                               # Elastic Container Registry & lifecycle policies
│   │   ├── ecs/                               # ECS Fargate Cluster, Task Defs & Services
│   │   ├── monitoring/                        # CloudWatch Alarms & SNS Alert Topics
│   │   ├── network/                           # 3-Tier VPC, Subnets, Gateways & Route Tables
│   │   ├── rds/                               # PostgreSQL RDS & AWS Secrets Manager integration
│   │   └── security_groups/                   # Chained least-privilege Security Groups
│   └── shared/
│       └── backend/                           # Remote state S3 bucket & DynamoDB lock table bootstrap
└── README.md                                  # Project landing page & index
```

---

## 🚀 Deployment Workflows

In enterprise operations, **all infrastructure and application deployments are driven via GitOps CI/CD pipelines**; local terminal applies (`tflocal`) are reserved strictly for rapid offline prototyping.

### 1. Primary Workflow: GitOps CI/CD Pipelines

#### A. Application Delivery ([`application-deployment-pipeline.yml`](.github/workflows/application-deployment-pipeline.yml))
- **Quality Gate:** Automated linting with `flake8`, Dockerfile syntax checks, and FastAPI import validation.
- **LocalStack CI Simulation:** Automatically provisions and deploys to a LocalStack container within GitHub Actions, pushes to LocalStack ECR, updates the ECS task definition, forces a rolling deployment in ECS Fargate, and runs automated `/health` and `/db-check` smoke tests.
- **AWS Cloud Mode:** Deploys via OIDC authentication directly to production AWS ECR and ECS Fargate.
- **Trigger:** Automatic on push to `app/**` or manual via `workflow_dispatch`:
  ```bash
  # Deploy app to Dev environment via GitHub Actions CLI
  gh workflow run application-deployment-pipeline.yml -f environment=dev -f app_dir="app/compose-demo"
  ```

#### B. Infrastructure Provisioning ([`iac-provision-pipeline.yml`](.github/workflows/iac-provision-pipeline.yml))
- **Automated Progressive Delivery:** Merging into `main` automatically deploys **Dev**, runs ALB health checks, promotes to **Staging**, and pauses before **Production** for manual DevOps approval.
- **Dynamic Targeting (Break-Glass):** Deploy specific modules on demand without hardcoded lists:
  ```bash
  gh workflow run iac-provision-pipeline.yml -f environment=dev -f target="module.ecs"
  ```

#### C. Infrastructure Quality Gate ([`ci.yml`](.github/workflows/ci.yml))
- Automatically runs `terraform fmt -check`, `terraform validate`, and **Checkov** security scans, posting plan diffs to PRs.

#### D. Guarded Teardown ([`iac-destroy-pipeline.yml`](.github/workflows/iac-destroy-pipeline.yml))
- Requires manual confirmation by typing `"DESTROY"` to tear down individual subsystems or full stacks:
  ```bash
  gh workflow run iac-destroy-pipeline.yml -f environment=dev -f confirm_destroy="DESTROY"
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
