# DevOps Assessment: AWS Infrastructure & CI/CD

This repository contains an AWS infrastructure setup using Terraform and automated CI/CD pipelines with GitHub Actions for deploying a containerized FastAPI application with PostgreSQL.

The setup is tested locally using LocalStack.

---

## Architecture Overview

The infrastructure implements an end-to-end 3-tier VPC across 2 Availability Zones (`ap-southeast-2a`, `ap-southeast-2b`) with external DNS, TLS termination, and supporting services:

```
                             [ User / Clients ]
                                      │
               ┌──────────────────────┴──────────────────────┐
               │                                             │
               ▼ (1. DNS Resolution)                         ▼ (2. HTTP/HTTPS Traffic)
  ┌─────────────────────────┐                   ┌─────────────────────────┐
  │   AWS Route 53 (DNS)    │                   │   INTERNET (Public Web) │
  │ (Managed outside TF)    │                   └────────────┬────────────┘
  └─────────────────────────┘                                │
                                                             ▼
                                                ┌─────────────────────────┐
                                                │ Internet Gateway (IGW)  │
                                                └────────────┬────────────┘
                                                             │
  ┌── AWS Region (ap-southeast-2) ───────────────────────────┼────────────────────────────────┐
  │                                                          │                                │
  │   [ AWS Certificate Manager (ACM) ] ──(SSL/TLS)──►       ▼                                │
  │                                                ┌───────────────────┐                      │
  │                                                │    Public ALB     │ (Port 80 / 443)      │
  │                                                └─────────┬─────────┘                      │
  │                                                          │                                │
  │  ┌── VPC ────────────────────────────────────────────────┼────────────────────────────┐   │
  │  │                                                       │                            │   │
  │  │                     ┌─────────────────────────────────┴─────────────────┐          │   │
  │  │                     ▼                                                   ▼          │   │
  │  │        ┌─────────────────────────┐                         ┌─────────────────────┐ │   │
  │  │        │   Availability Zone A   │                         │ Availability Zone B │ │   │
  │  │        │                         │                         │                     │ │   │
  │  │        │ ┌─────────────────────┐ │                         │ ┌─────────────────┐ │ │   │
  │  │        │ │ Public Subnet       │ │                         │ │ Public Subnet   │ │ │   │
  │  │        │ │   [ NAT Gateway A ] │◄──(Egress)──┐ ┌──(Egress)─┼─► [ NAT Gateway B]│ │ │   │
  │  │        │ └─────────────────────┘ │           │ │           │ └─────────────────┘ │ │   │
  │  │        │                         │           │ │           │                     │ │   │
  │  │        │ ┌─────────────────────┐ │           │ │           │ ┌─────────────────┐ │ │   │
  │  │        │ │ Private App Subnet  │ │           │ │           │ │ Private App Sub │ │ │   │
  │  │        │ │   [ ECS Task A ]    │─┴───────────┘ └───────────┴─│   [ ECS Task B] │ │ │   │
  │  │        │ └──────────┬──────────┘                             └──────────┬──────┘ │ │   │
  │  │        │            │ (Port 5432)                                       │        │ │   │
  │  │        │            └───────────────────┐       ┌───────────────────────┘        │ │   │
  │  │        │                                ▼       ▼                                │ │   │
  │  │        │ ┌─────────────────────┐     ┌─────────────────────┐                     │ │   │
  │  │        │ │ Private DB Subnet   │     │ Private DB Subnet   │                     │ │   │
  │  │        │ │  [ RDS Primary ]    │◄───►│  [ RDS Standby ]    │                     │ │   │
  │  │        │ │  (PostgreSQL 16.1)  │Sync │  (Prod Multi-AZ)    │                     │ │   │
  │  │        │ └─────────────────────┘Repl └─────────────────────┘                     │ │   │
  │  │        └─────────────────────────────────────────────────────────────────────────┘ │   │
  │  └────────────────────────────────────────────────────────────────────────────────────┘   │
  │                                                                                           │
  │  ┌── Supporting Regional Services ────────────────────────────────────────────────────┐   │
  │  │  • Amazon ECR: Stores immutable container images pushed by GitHub Actions CI/CD    │   │
  │  │  • AWS Secrets Manager: Injects DB credentials & environment variables into ECS    │   │
  │  │  • Amazon CloudWatch & SNS: Collects metrics/logs and triggers email alert alarms  │   │
  │  └────────────────────────────────────────────────────────────────────────────────────┘   │
  └───────────────────────────────────────────────────────────────────────────────────────────┘
```

### Environment Tiers

| Environment | Architecture | NAT Gateways | RDS Deployment | Deployment Trigger |
| :--- | :--- | :--- | :--- | :--- |
| **`dev`** | Single-AZ | 1 Gateway | Single Instance (`db_multi_az = false`) | Push to `main` |
| **`staging`** | Single-AZ | 1 Gateway | Single Instance (`db_multi_az = false`) | Auto after Dev verification |
| **`prod`** | Multi-AZ | 2 Gateways | Multi-AZ (`db_multi_az = true`) | Manual approval |

---

## Infrastructure as Code (IaC)

Terraform configurations are structured as reusable modules under `iac/modules/`:

- **`network`**: VPC, public/private subnets across 2 AZs (`ap-southeast-2a`, `ap-southeast-2b`), Internet Gateway, route tables, and NAT Gateways.
- **`security_groups`**: Least-privilege rules chaining ALB -> ECS (port 8000) -> RDS (port 5432).
- **`alb`**: Application Load Balancer, target group, and health check route (`/health`).
- **`ecs`**: ECS Fargate cluster, task definition, and service with rolling deployment.
- **`ecr`**: Container registry with image lifecycle policies.
- **`rds`**: PostgreSQL database with credentials managed via AWS Secrets Manager.
- **`monitoring`**: CloudWatch alarms (ALB 5xx errors, ECS memory) and SNS alert topics.

Remote state is stored in S3 with DynamoDB locking (`iac/shared/backend/`).

---

## CI/CD Pipelines

Workflows are defined in `.github/workflows/`:

1. **`ci.yml`**: Runs `terraform fmt`, `validate`, and Checkov security scan on pull requests.
2. **`iac-provision-pipeline.yml`**: Deploys Terraform infrastructure progressively (`dev` -> `staging` -> `prod`). Supports targeted deployment via workflow inputs (e.g. `target: module.ecs`).
3. **`application-deployment-pipeline.yml`**: Lints the app, builds the Docker image, pushes to ECR, and triggers ECS rolling updates.
   - Dev & Staging: tagged with commit SHA.
   - Production: requires a release version tag (e.g. `v1.0.0`).
4. **`iac-destroy-pipeline.yml`**: Tears down infrastructure. Requires typing `DESTROY` as an input confirmation.

---

## Secrets Management (AWS Secrets Manager)

Application configuration and database credentials are stored in AWS Secrets Manager (ASM) instead of GitHub Actions secrets:

- **`tru-demo-<env>-db-credentials`**: Database host, port, username, password, and database URL.
- **`tru-demo-<env>-app-secrets`**: Application environment variables (`APP_ENV`, `LOG_LEVEL`, API keys).

ECS tasks load these secrets directly at container startup via the ECS Task Execution Role. Secrets can be updated in AWS Secrets Manager, and applying an ECS rolling deployment reloads the application with the new values without rebuilding images.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                             # PR validation & security checks
│       ├── iac-provision-pipeline.yml         # Terraform provision pipeline
│       ├── iac-destroy-pipeline.yml           # Terraform destroy pipeline
│       └── application-deployment-pipeline.yml# App build & ECS deployment
├── app/
│   ├── compose-demo/                          # FastAPI demo application
│   └── k8s-event-api/                         # Kubernetes event API reference
├── docs/
│   ├── HOW_TO_USE.md                          # Commands for running pipelines & LocalStack
│   └── DEPLOYMENT_GUIDE.md                    # Detailed deployment & architecture notes
├── iac/
│   ├── environments/                          # dev, staging, prod stacks
│   ├── modules/                               # Terraform modules (vpc, rds, ecs, alb, etc.)
│   └── shared/backend/                        # S3 & DynamoDB remote state backend
└── README.md
```

---

## Documentation

- **[How-To-Use Guide](docs/HOW_TO_USE.md)**: Instructions and commands for triggering pipelines, running LocalStack locally, updating secrets, and running health checks.
- **[Deployment & Architecture Guide](docs/DEPLOYMENT_GUIDE.md)**: Detailed technical specifications, module parameters, and LocalStack verification details.
