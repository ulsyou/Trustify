# How-To-Use Guide & Operational Runbook

This guide covers operational execution instructions for the **Trustify** technical assessment repository, including triggering CI/CD pipelines via GitHub UI / CLI, running local sandbox tests with LocalStack, managing secrets in AWS Secrets Manager, and verifying live services.

---

## 1. Running CI/CD Pipelines

All continuous integration, deployment, and teardown operations are orchestrated through GitHub Actions.

### 1.1 Triggering via GitHub Web UI

1. Navigate to the **Actions** tab in the repository: `https://github.com/<owner>/<repo>/actions`.
2. Select the desired workflow from the left sidebar:
   - **`Application Deployment Pipeline`**: Builds Docker image, pushes to ECR, and deploys to ECS.
   - **`IaC Provision Pipeline`**: Deploys Terraform infrastructure across Dev, Staging, and Prod.
   - **`IaC Destroy Pipeline`**: Destroys infrastructure with safety confirmation.
3. Click the **Run workflow** dropdown on the right.
4. Select the branch (`main`) and fill in the required input parameters (e.g., `environment`, `image_tag`, `target`, or `confirm_destroy`).
5. Click **Run workflow** to initiate execution.

---

### 1.2 Triggering via GitHub CLI (`gh`)

If you have the [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated (`gh auth login`):

#### A. Application Deployment
Deploys application containers to ECS Fargate.
```bash
# Deploy to Dev (uses latest commit SHA automatically if tag omitted)
gh workflow run application-deployment-pipeline.yml -f environment=dev

# Deploy to Staging with a specific tag
gh workflow run application-deployment-pipeline.yml -f environment=staging -f image_tag=v1.0.0

# Deploy to Production (strictly requires release tag like v1.0.0)
gh workflow run application-deployment-pipeline.yml -f environment=prod -f image_tag=v1.0.0
```

#### B. Infrastructure Provisioning
Provisions or updates Terraform infrastructure.
```bash
# Progressive rollout across Dev -> Staging -> Prod
gh workflow run iac-provision-pipeline.yml -f environment=dev

# Target a specific module (Break-Glass / targeted update)
gh workflow run iac-provision-pipeline.yml -f environment=dev -f target="module.ecs"
gh workflow run iac-provision-pipeline.yml -f environment=dev -f target="module.rds"
```

#### C. Guarded Infrastructure Teardown
Tears down infrastructure resources safely.
```bash
# Destroy Dev environment (requires exact confirmation string 'DESTROY')
gh workflow run iac-destroy-pipeline.yml -f environment=dev -f confirm_destroy="DESTROY"

# Destroy specific module in Staging
gh workflow run iac-destroy-pipeline.yml -f environment=staging -f target="module.ecs" -f confirm_destroy="DESTROY"
```

#### D. Monitoring Workflow Execution
```bash
# View recent workflow runs
gh run list

# Watch progress of the latest run interactively
gh run watch
```

---

## 2. LocalStack Developer Sandbox

For local development and testing without incurring AWS cloud costs, the infrastructure is fully compatible with LocalStack Pro using `tflocal` and `awslocal`.

### 2.1 Starting LocalStack
Ensure Docker Desktop is running, then start LocalStack:
```bash
# Start LocalStack via CLI
lstk start

# Or start LocalStack via Docker
docker run -d --name localstack -p 4566:4566 -e LOCALSTACK_AUTH_TOKEN=$LOCALSTACK_AUTH_TOKEN localstack/localstack-pro:latest
```

### 2.2 Bootstrapping Remote State
Initialize the S3 state backend and DynamoDB lock table locally:
```bash
cd iac/shared/backend
tflocal init
tflocal apply -auto-approve
```

### 2.3 Provisioning Environments
Navigate to any environment stack to plan and apply:
```bash
# Deploy Dev environment
cd ../../environments/dev
tflocal init
tflocal plan -out=dev.tfplan
tflocal apply dev.tfplan

# Deploy Staging or Prod
cd ../staging
tflocal init && tflocal apply -auto-approve

cd ../prod
tflocal init && tflocal apply -auto-approve
```

### 2.4 Inspecting Local Resources
Verify provisioned resources using `awslocal`:
```bash
# Check Application Load Balancer
awslocal elbv2 describe-load-balancers --region ap-southeast-2 --output table

# Check ECS Clusters & Running Tasks
awslocal ecs list-clusters --region ap-southeast-2
awslocal ecs list-tasks --cluster tru-demo-dev-ecs-cluster --region ap-southeast-2

# Check RDS Database Instances
awslocal rds describe-db-instances --region ap-southeast-2 --output table

# Check AWS Secrets Manager Secrets
awslocal secretsmanager list-secrets --region ap-southeast-2 --output table
```

---

## 3. Managing & Rotating Secrets (AWS Secrets Manager)

Application configuration and database credentials are decoupled from GitHub Actions and managed directly in **AWS Secrets Manager (ASM)**.

### 3.1 Secret Locations
Each environment creates two secrets:
1. `tru-demo-<env>-db-credentials`: Database connection details (`host`, `port`, `username`, `password`, `dbname`, `database_url`).
2. `tru-demo-<env>-app-secrets`: Application runtime configuration (`APP_ENV`, `LOG_LEVEL`, API keys).

### 3.2 Reading Secrets
```bash
# Retrieve application secrets for Dev
aws secretsmanager get-secret-value \
  --secret-id tru-demo-dev-app-secrets \
  --region ap-southeast-2 \
  --query SecretString \
  --output text
```

### 3.3 Updating / Rotating Application Configuration
To change runtime variables (e.g. adjust log levels or update tokens) without changing code or rebuilding container images:

1. Update the secret value in AWS Secrets Manager:
```bash
aws secretsmanager put-secret-value \
  --secret-id tru-demo-dev-app-secrets \
  --region ap-southeast-2 \
  --secret-string '{"APP_ENV":"dev","LOG_LEVEL":"DEBUG","FEATURE_NEW_API":"true"}'
```

2. Trigger a rolling update in ECS to inject updated secrets into new Fargate tasks:
```bash
aws ecs update-service \
  --cluster tru-demo-dev-ecs-cluster \
  --service tru-demo-dev-service \
  --force-new-deployment \
  --region ap-southeast-2
```

---

## 4. Verification & Smoke Testing

### 4.1 Automated ALB Health Endpoint Check
Once the deployment completes, query the Application Load Balancer DNS:
```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names tru-demo-dev-alb \
  --region ap-southeast-2 \
  --query "LoadBalancers[0].DNSName" \
  --output text)

# Test root endpoint
curl -i "http://${ALB_DNS}/"

# Test health check endpoint (used by ALB Target Group)
curl -i "http://${ALB_DNS}/health"

# Test database connectivity endpoint
curl -i "http://${ALB_DNS}/db-health"
```

Expected HTTP response for `/health`:
```json
{
  "status": "healthy",
  "environment": "dev",
  "version": "v1.0.0"
}
```

---

## 5. Teardown & Clean Up

To avoid unexpected resource usage, tear down environments when testing is complete:

### 5.1 Teardown via Pipeline
Use the `iac-destroy-pipeline.yml` workflow via GitHub Actions UI or CLI:
```bash
gh workflow run iac-destroy-pipeline.yml -f environment=dev -f confirm_destroy="DESTROY"
```

### 5.2 Teardown via LocalStack / Local CLI
```bash
cd iac/environments/dev
tflocal destroy -auto-approve

cd ../staging
tflocal destroy -auto-approve

cd ../prod
tflocal destroy -auto-approve

# Teardown backend state
cd ../../shared/backend
tflocal destroy -auto-approve
```
