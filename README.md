# DevOps Technical Assessment: AWS Infrastructure & CI/CD Pipelines

[![Terraform](https://img.shields.io/badge/IaC-Terraform_1.9-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS_ap--southeast--2-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![LocalStack](https://img.shields.io/badge/Emulation-LocalStack_Pro-0052CC?logo=localstack&logoColor=white)](https://localstack.cloud/)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL_16.1-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

This repository contains the technical assessment implementation for **Trustify**, demonstrating an enterprise cloud infrastructure on AWS orchestrated via modular Terraform Infrastructure as Code (IaC), zero-trust secrets management with AWS Secrets Manager, and automated GitOps CI/CD delivery pipelines.

---

## Architecture Overview

The infrastructure deploys a containerized FastAPI application with a PostgreSQL database following a 3-tier VPC architecture designed for traffic isolation, high availability, and least-privilege security:

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

## Infrastructure as Code (IaC) Overview

The Terraform codebase follows a reusable, modular pattern with separated state backends for each environment tier.

### 1. Core Modules (`iac/modules/`)
- **`network`**: 3-tier VPC spanning 2 Availability Zones (`ap-southeast-2a`, `ap-southeast-2b`), public subnets with Internet Gateway, private application subnets, private database subnets, and NAT Gateways configured per tier.
- **`security_groups`**: Least-privilege ingress and egress chaining. ALB accepts HTTP port 80; ECS tasks only accept traffic originating from the ALB security group on port 8000; RDS only accepts PostgreSQL traffic on port 5432 from ECS tasks.
- **`alb`**: Internet-facing Application Load Balancer with HTTP listeners, dynamic target groups, and automated `/health` probing.
- **`ecs`**: ECS Fargate cluster, task definitions, task execution IAM roles, and service definitions with rolling deployment (`ignore_changes = [desired_count]`).
- **`ecr`**: Private container registry with immutable image tags and automated lifecycle cleanup policies.
- **`rds`**: PostgreSQL 16.1 database with automated AWS Secrets Manager integration for credential generation and storage.
- **`monitoring`**: CloudWatch alarms monitoring ALB 5XX error rates, RDS CPU utilization, and SNS notification topics.

### 2. Remote State Management
State files are isolated per environment within an S3 bucket configured with server-side encryption, versioning, and DynamoDB distributed state locking (`iac/shared/backend`).

---

## CI/CD Pipelines Overview

All infrastructure and application delivery workflows are managed through GitHub Actions:

### 1. Application Deployment Pipeline ([`application-deployment-pipeline.yml`](.github/workflows/application-deployment-pipeline.yml))
- **Quality Gates:** Automated linting with `flake8`, Dockerfile static checks, and FastAPI dependency checks.
- **Build & Push:** Single container image build pushed to Amazon ECR.
- **Progressive Delivery:** Sequential rollout to **Dev** &rarr; automated ALB health check &rarr; **Staging** promotion &rarr; manual approval gate &rarr; **Production**.
- **Versioning Policy:**
  - **Dev & Staging:** Automatically tagged with the Git commit SHA (`${{ github.sha }}`) and `:latest`.
  - **Production:** Strictly requires an explicit semver release tag (e.g. `v1.0.0`); commit SHA deployments to Production are rejected.

### 2. Infrastructure Provisioning Pipeline ([`iac-provision-pipeline.yml`](.github/workflows/iac-provision-pipeline.yml))
- **Progressive Delivery:** Automated deployment across Dev, Staging, and Production triggered on push to `main`.
- **Manual Dispatch & Targeted Updates:** Supports running targeted module deployments (e.g., updating only `module.ecs` or `module.rds`) for emergency fixes or rapid iteration without modifying entire environments.

### 3. Infrastructure Quality Gate ([`ci.yml`](.github/workflows/ci.yml))
- Runs on pull requests to ensure code hygiene and security compliance before merging.
- Executes `terraform fmt -check`, `terraform validate`, static security scanning via **Checkov**, and generates speculative plan summaries on pull requests.

### 4. Guarded Teardown Pipeline ([`iac-destroy-pipeline.yml`](.github/workflows/iac-destroy-pipeline.yml))
- Controlled teardown workflow protected by an explicit confirmation requirement (`confirm_destroy = "DESTROY"`), preventing accidental resource termination.

> 💡 *For step-by-step instructions on triggering pipelines via the GitHub UI and GitHub CLI (`gh`), see the [How-To-Use Guide](docs/HOW_TO_USE.md).*

---

## Centralized Secrets & Configuration (AWS Secrets Manager)

To enforce zero-trust security and decoupled operations:
- **Zero Secrets in CI/CD:** GitHub Actions runners do not store application environment variables, API tokens, or database passwords. Runners only use an AWS OIDC IAM role for deployment authentication.
- **Direct ECS Fargate Injection:** Secrets and runtime variables are injected into container tasks at launch via the ECS Task Execution Role (`secretsmanager:GetSecretValue`).
- **Dedicated Secret Stores per Tier:**
  - `tru-demo-<env>-db-credentials`: Managed RDS PostgreSQL credentials (`host`, `port`, `username`, `password`, `dbname`, `database_url`).
  - `tru-demo-<env>-app-secrets`: Runtime application configuration (`APP_ENV`, `LOG_LEVEL`, third-party keys).
- **Zero-Downtime Configuration Updates:** Updating secrets in Secrets Manager applies instantly to running services via an ECS rolling deployment without modifying code or rebuilding Docker images.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                             # IaC format checks, validation, Checkov scan & PR plan comments
│       ├── iac-provision-pipeline.yml         # IaC progressive provisioning + targeted dispatch
│       ├── iac-destroy-pipeline.yml           # Guarded IaC teardown pipeline with 'DESTROY' confirmation
│       └── application-deployment-pipeline.yml# Application build, test, ECR push & ECS progressive rollout
├── app/
│   ├── compose-demo/                          # FastAPI demo with PostgreSQL connection & health endpoints
│   └── k8s-event-api/                         # Kubernetes event API reference implementation
├── docs/
│   ├── HOW_TO_USE.md                          # Practical runbook: pipeline triggers, LocalStack & secret rotation
│   └── DEPLOYMENT_GUIDE.md                    # Deep-dive architecture runbook & LocalStack simulation verification
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
└── README.md                                  # Architectural & conceptual project overview
```

---

## Documentation Index

- 📖 **[How-To-Use Guide & Operational Runbook](docs/HOW_TO_USE.md)**: Operational guide containing execution instructions for running pipelines (UI & GitHub CLI), LocalStack developer sandbox testing, secret rotation, and smoke testing.
- 📐 **[Architecture & Deployment Runbook](docs/DEPLOYMENT_GUIDE.md)**: In-depth technical architecture, module parameter matrix, and LocalStack simulation validation logs.
