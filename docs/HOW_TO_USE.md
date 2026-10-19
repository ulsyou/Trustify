# How to Use

Instructions for triggering pipelines via the GitHub Web UI, running the project locally with LocalStack, updating secrets, and testing endpoints.

---

## 1. Running Pipelines (GitHub Actions Web UI)

All continuous integration, deployment, and teardown workflows run on GitHub Actions.

To run a workflow manually:
1. Navigate to the **Actions** tab in the GitHub repository.
2. Select the workflow from the left sidebar.
3. Click the **Run workflow** dropdown on the right, select branch `main`, fill in any inputs, and click **Run workflow**.

### Available Workflows

- **Application Deployment Pipeline** (`application-deployment-pipeline.yml`):
  - Builds the Docker image, pushes to ECR, and deploys to ECS Fargate.
  - Inputs:
    - `environment`: `dev`, `staging`, or `prod`.
    - `image_tag`: Image version tag (optional for dev/staging which default to commit SHA, required for prod like `v1.0.0`).

- **IaC Provision Pipeline** (`iac-provision-pipeline.yml`):
  - Plans and applies Terraform infrastructure.
  - Automatically runs across `dev` -> `staging` -> `prod` on push to `main`.
  - Manual inputs:
    - `environment`: `dev`, `staging`, or `prod`.
    - `target`: (Optional) Specific module to apply (e.g. `module.ecs` or `module.rds`). Leave blank to apply the full stack.

- **IaC Destroy Pipeline** (`iac-destroy-pipeline.yml`):
  - Tears down Terraform-managed infrastructure.
  - Inputs:
    - `environment`: `dev`, `staging`, or `prod`.
    - `target`: (Optional) Specific module to destroy.
    - `confirm_destroy`: Safety confirmation. Must type `DESTROY` exactly.

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
curl -i "http://${ALB_DNS}/db-check"
```

Expected output for `/health`:
```json
{"status": "ok"}
```

Expected output for `/db-check`:
```json
{"db_status": "ok", "result": 1}
```

---

## 5. Teardown & Cleanup

### Via GitHub Actions
1. Go to **Actions** &rarr; select **IaC Destroy Pipeline**.
2. Click **Run workflow**.
3. Select the target `environment` and type `DESTROY` in the `confirm_destroy` input field.

### Via LocalStack
```bash
cd iac/environments/dev
tflocal destroy -auto-approve

cd ../../shared/backend
tflocal destroy -auto-approve

lstk stop
```
