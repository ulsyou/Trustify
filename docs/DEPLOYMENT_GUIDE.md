# Deployment & Architecture Guide

Technical reference for the AWS infrastructure architecture, Terraform modules, and CI/CD pipelines.

---

## 1. Network Architecture

The infrastructure implements a 3-tier VPC across 2 Availability Zones (`ap-southeast-2a`, `ap-southeast-2b`):

```
                      INTERNET
                         │
                         ▼
             [ Internet Gateway (IGW) ]
                         │
        ┌────────────────┴────────────────┐
        │       Public Subnets (x2)       │
        │   ┌─────────────────────────┐   │
        │   │ Application Load Balancer│  │ (Port 80 HTTP Ingress)
        │   └────────────┬────────────┘   │
        │                │                │
        │   [ NAT Gateway & Elastic IP ]  │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │     Private App Subnets (x2)    │
        │   ┌────────────▼────────────┐   │
        │   │  ECS Fargate Container  │   │ (Port 8000 FastAPI)
        │   └────────────┬────────────┘   │
        └────────────────┼────────────────┘
                         │ (Port 5432)
        ┌────────────────┼────────────────┐
        │      Private DB Subnets (x2)    │
        │   ┌────────────▼────────────┐   │
        │   │  RDS PostgreSQL 16.1    │   │ (Isolated Database Tier)
        │   └─────────────────────────┘   │
        └─────────────────────────────────┘
```

### Subnet Allocation

Each environment uses a `/16` VPC partitioned into `/20` subnets:

| Subnet Type | Dev (`10.10.0.0/16`) | Staging (`10.20.0.0/16`) | Prod (`10.30.0.0/16`) | Target Routing |
| :--- | :--- | :--- | :--- | :--- |
| **Public AZ-a** | `10.10.0.0/20` | `10.20.0.0/20` | `10.30.0.0/20` | Internet Gateway (IGW) |
| **Public AZ-b** | `10.10.16.0/20` | `10.20.16.0/20` | `10.30.16.0/20` | Internet Gateway (IGW) |
| **App AZ-a** | `10.10.32.0/20` | `10.20.32.0/20` | `10.30.32.0/20` | NAT Gateway 1 |
| **App AZ-b** | `10.10.48.0/20` | `10.20.48.0/20` | `10.30.48.0/20` | NAT Gateway 1 (or 2 in Prod) |
| **DB AZ-a** | `10.10.64.0/20` | `10.20.64.0/20` | `10.30.64.0/20` | Isolated (Local VPC only) |
| **DB AZ-b** | `10.10.80.0/20` | `10.20.80.0/20` | `10.30.80.0/20` | Isolated (Local VPC only) |

---

## 2. Environment Matrix

| Parameter | Dev | Staging | Prod |
| :--- | :--- | :--- | :--- |
| **VPC CIDR** | `10.10.0.0/16` | `10.20.0.0/16` | `10.30.0.0/16` |
| **High Availability** | Single-AZ | Single-AZ | Multi-AZ |
| **NAT Gateways** | 1 | 1 | 2 (1 per AZ) |
| **RDS Instance Class** | `db.t4g.micro` | `db.t4g.micro` | `db.t4g.small` |
| **RDS Multi-AZ** | `false` | `false` | `true` |
| **ECS Task CPU / RAM** | 256 / 512 | 256 / 512 | 512 / 1024 |
| **ECS Desired Count** | 1 | 1 | 2 |
| **Promotion Trigger** | Push to `main` | Auto after Dev test | Manual Approval |

---

## 3. Security Groups & Traffic Rules

Traffic flows strictly from outer to inner tiers:

1. **ALB Security Group (`alb-sg`)**:
   - Ingress: Port 80 from `0.0.0.0/0`.
   - Egress: Port 8000 to `app-sg`.

2. **ECS Security Group (`app-sg`)**:
   - Ingress: Port 8000 only from `alb-sg`.
   - Egress: Port 5432 to `db-sg`, HTTPS (443) to internet/VPC endpoints for ECR and Secrets Manager.

3. **RDS Security Group (`db-sg`)**:
   - Ingress: Port 5432 only from `app-sg`.
   - Egress: None (fully private database tier).

---

## 4. Components & Terraform Modules

- **`network`**: Manages VPC, subnets, route tables, internet gateway, and NAT gateways.
- **`security_groups`**: Creates least-privilege security groups for ALB, ECS, and RDS.
- **`alb`**: Public load balancer, target group (`/health` probe), and HTTP listener.
- **`ecs`**: Fargate cluster, task definition, IAM execution/task roles, CloudWatch log group, and service configuration. Uses `lifecycle { ignore_changes = [desired_count] }` to allow autoscaling.
- **`ecr`**: Container repository with lifecycle policy (retains last 30 tagged images).
- **`rds`**: PostgreSQL 16.1 engine, subnet group across 2 AZs, and automated credentials generated in Secrets Manager.
- **`monitoring`**: CloudWatch metric alarms for ALB 5xx errors and high ECS memory, hooked to an SNS alert topic.

---

## 5. Secrets Management Architecture

To avoid storing credentials or application configs in GitHub Actions:
- **`tru-demo-<env>-db-credentials`**: Contains database host, port, username, password, and connection string.
- **`tru-demo-<env>-app-secrets`**: Contains application environment variables (`APP_ENV`, `LOG_LEVEL`, API keys).
- **Injection Mechanism**: The ECS Task Execution Role has IAM permissions (`secretsmanager:GetSecretValue`) to inject these values as environment variables directly at container launch.
- **Configuration Updates**: Changes made in AWS Secrets Manager are picked up on the next rolling update (`aws ecs update-service --force-new-deployment`).

---

## 6. CI/CD Workflows

The repository uses GitHub Actions for continuous integration and delivery:

1. **PR Quality Check ([`ci.yml`](../.github/workflows/ci.yml))**:
   - Runs `terraform fmt -check` and `terraform validate`.
   - Runs `checkov` security scanning on Terraform code.
   - Generates speculative plan diff and posts summary to PR comments.

2. **Infrastructure Provisioning ([`iac-provision-pipeline.yml`](../.github/workflows/iac-provision-pipeline.yml))**:
   - Automatically plans and applies changes to `dev` upon merge to `main`.
   - Runs curl health check against ALB.
   - Automatically applies to `staging`.
   - Pauses for manual approval before applying to `prod`.
   - Supports targeted execution via the `target` input parameter (e.g., `module.ecs`).

3. **Application Delivery ([`application-deployment-pipeline.yml`](../.github/workflows/application-deployment-pipeline.yml))**:
   - Lints application code with `flake8`.
   - Builds container image and pushes to ECR.
   - Deploys progressively to Dev &rarr; Staging &rarr; Prod.
   - Enforces tag policies: Dev/Staging use commit SHA; Prod strictly requires a release version tag (e.g., `v1.0.0`).

4. **Infrastructure Teardown ([`iac-destroy-pipeline.yml`](../.github/workflows/iac-destroy-pipeline.yml))**:
   - Requires manual entry of `confirm_destroy: "DESTROY"`.
   - Can destroy individual modules or entire environments.
