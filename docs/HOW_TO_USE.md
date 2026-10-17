# How to Use

Instructions for triggering pipelines, running the project locally with LocalStack, updating secrets, and testing endpoints.

---

## 1. Running Pipelines (GitHub Actions)

All continuous integration, deployment, and teardown workflows run on GitHub Actions.

### Trigger via GitHub Web UI

1. Go to the **Actions** tab in GitHub.
2. Select a workflow from the left sidebar:
   - **Application Deployment Pipeline**: builds Docker image, pushes to ECR, and deploys to ECS.
   - **IaC Provision Pipeline**: plans and applies Terraform infrastructure (`dev`, `staging`, `prod`).
   - **IaC Destroy Pipeline**: tears down infrastructure with confirmation.
3. Click **Run workflow**, choose branch `main`, enter any inputs, and click **Run workflow**.

---

### Trigger via GitHub CLI (`gh`)

#### Application Deployment
```bash
# Deploy to Dev (uses latest commit SHA)
gh workflow run application-deployment-pipeline.yml -f environment=dev

# Deploy to Staging with a specific tag
gh workflow run application-deployment-pipeline.yml -f environment=staging -f image_tag=v1.0.0

# Deploy to Production (requires release tag)
gh workflow run application-deployment-pipeline.yml -f environment=prod -f image_tag=v1.0.0
```

#### Infrastructure Provisioning
```bash
# Progressive deploy across Dev -> Staging -> Prod
gh workflow run iac-provision-pipeline.yml -f environment=dev

# Deploy a specific module only
gh workflow run iac-provision-pipeline.yml -f environment=dev -f target="module.ecs"
gh workflow run iac-provision-pipeline.yml -f environment=dev -f target="module.rds"
```

#### Infrastructure Teardown
```bash
# Destroy Dev environment (requires confirm_destroy="DESTROY")
gh workflow run iac-destroy-pipeline.yml -f environment=dev -f confirm_destroy="DESTROY"

# Destroy specific module
gh workflow run iac-destroy-pipeline.yml -f environment=dev -f target="module.ecs" -f confirm_destroy="DESTROY"
```

#### Check Workflow Runs
```bash
# List recent runs
gh run list

# Watch active run
gh run watch
```

---

## 2. Running Locally with LocalStack

The infrastructure can be tested locally using LocalStack Pro with `tflocal` and `awslocal`.

### Start LocalStack
```bash
lstk start
```

### Initialize Remote State Backend
```bash
cd iac/shared/backend
tflocal init
tflocal apply -auto-approve
```

### Deploy an Environment
```bash
# Deploy Dev
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

### Inspect Local Resources
```bash
# Check Load Balancers
awslocal elbv2 describe-load-balancers --region ap-southeast-2 --output table

# Check ECS Clusters & Tasks
awslocal ecs list-clusters --region ap-southeast-2
awslocal ecs list-tasks --cluster tru-demo-dev-ecs-cluster --region ap-southeast-2

# Check RDS Instances
awslocal rds describe-db-instances --region ap-southeast-2 --output table

# Check Secrets Manager
awslocal secretsmanager list-secrets --region ap-southeast-2 --output table
```

---

## 3. Managing Secrets (AWS Secrets Manager)

Environment variables and database credentials are stored in AWS Secrets Manager:

- `tru-demo-<env>-db-credentials`: database connection info (`host`, `port`, `username`, `password`, `dbname`, `database_url`).
- `tru-demo-<env>-app-secrets`: app config (`APP_ENV`, `LOG_LEVEL`, API keys).

### View a Secret
```bash
aws secretsmanager get-secret-value \
  --secret-id tru-demo-dev-app-secrets \
  --region ap-southeast-2 \
  --query SecretString \
  --output text
```

### Update Config and Reload App
1. Update secret values:
```bash
aws secretsmanager put-secret-value \
  --secret-id tru-demo-dev-app-secrets \
  --region ap-southeast-2 \
  --secret-string '{"APP_ENV":"dev","LOG_LEVEL":"DEBUG"}'
```

2. Trigger a rolling restart in ECS to pick up new values without rebuilding images:
```bash
aws ecs update-service \
  --cluster tru-demo-dev-ecs-cluster \
  --service tru-demo-dev-service \
  --force-new-deployment \
  --region ap-southeast-2
```

---

## 4. Verification & Testing

Query the Application Load Balancer endpoints to verify service health:

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names tru-demo-dev-alb \
  --region ap-southeast-2 \
  --query "LoadBalancers[0].DNSName" \
  --output text)

# Test root endpoint
curl -i "http://${ALB_DNS}/"

# Test health check endpoint
curl -i "http://${ALB_DNS}/health"

# Test database connection endpoint
curl -i "http://${ALB_DNS}/db-health"
```

Expected output for `/health`:
```json
{
  "status": "healthy",
  "environment": "dev",
  "version": "v1.0.0"
}
```

---

## 5. Teardown & Cleanup

### Via Pipeline
```bash
gh workflow run iac-destroy-pipeline.yml -f environment=dev -f confirm_destroy="DESTROY"
```

### Via LocalStack
```bash
cd iac/environments/dev
tflocal destroy -auto-approve

cd ../../shared/backend
tflocal destroy -auto-approve

lstk stop
```
