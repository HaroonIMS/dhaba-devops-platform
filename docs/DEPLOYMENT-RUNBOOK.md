# Dhaba DevOps Platform — Deployment Runbook

## 1. Purpose

This runbook documents the CI/CD deployment process, staging environment verification, Kubernetes access, troubleshooting, and recovery procedures for the Dhaba DevOps Platform.

The application is deployed to a K3s cluster hosted on an AWS EC2 instance. GitHub Actions automates validation, Docker image publishing, and staging deployment.

## 2. Infrastructure Overview

| Component | Configuration |
|---|---|
| Cloud provider | AWS |
| Region | ap-southeast-2 |
| Compute | EC2 |
| Container orchestration | K3s |
| Container registry | Amazon ECR |
| Deployment namespace | staging |
| Remote command execution | AWS Systems Manager |
| CI/CD | GitHub Actions |
| AWS authentication | GitHub Actions OIDC |

### Application services

| Service | Kubernetes Deployment |
|---|---|
| Web frontend | web |
| Menu service | menu-api |
| Order service | orders-api |
| Kitchen background worker | kitchen-worker |
| Statistics service | stats-api |

PostgreSQL and Redis provide supporting application infrastructure.

The CI pipeline also builds an `ops-monitor` image. This image is published to ECR but is not part of the five-service staging deployment.

## 3. CI/CD Pipeline

The workflow is defined in:

`.github/workflows/ci.yml`

### Stage 1: Application validation

GitHub Actions runs five independent jobs:

| Service | Validation |
|---|---|
| Web | npm install, lint, tests, production build |
| Menu API | Ruff checks and pytest |
| Orders API | Go tests, vet, and build |
| Kitchen Worker | Maven verify |
| Stats API | PHPUnit and PHPStan |

The image publishing job depends on all five validation jobs succeeding.

### Stage 2: Docker image publishing

On pushes to `main`, GitHub Actions:

1. Assumes the configured AWS IAM role using OIDC.
2. Authenticates to Amazon ECR.
3. Sets up Docker Buildx.
4. Builds and pushes six images.
5. Tags each image with the Git commit SHA.

The images are built for `linux/amd64`.

The image repositories are:

- `dhaba-devops-platform/web`
- `dhaba-devops-platform/menu-api`
- `dhaba-devops-platform/orders-api`
- `dhaba-devops-platform/kitchen-worker`
- `dhaba-devops-platform/stats-api`
- `dhaba-devops-platform/ops-monitor`

### Stage 3: Staging deployment

The deployment job runs after successful image publishing.

It uses:

- AWS OIDC authentication.
- AWS Systems Manager Run Command.
- The EC2 instance hosting the K3s cluster.
- The Git commit SHA as the deployment image tag.

The remote deployment procedure:

1. Checks that the EC2 deployment repository has no uncommitted changes.
2. Fetches the latest `main` branch.
3. Checks out the target commit in detached HEAD mode.
4. Updates the five application deployments sequentially.
5. Waits for each Kubernetes rollout, with a 300-second timeout.
6. Displays the final staging deployment status.

GitHub Actions polls the SSM command for completion. The workflow fails if the command fails, times out, or is cancelled.

**Important:** The current pipeline does not implement automatic rollback.

## 4. GitHub Actions Configuration

The deployment workflow requires the following GitHub repository variables:

| Variable | Purpose |
|---|---|
| AWS_ROLE_ARN | IAM role assumed through OIDC |
| AWS_REGION | AWS deployment region |

The workflow uses the following permissions:

- `contents: read`
- `id-token: write` for AWS OIDC authentication.

AWS access keys are not stored in the repository or workflow.

The deployment job uses the configured EC2 instance ID and ECR registry. Changes to these infrastructure values must be reflected in the workflow configuration.

## 5. Deploying a New Version

### Normal deployment procedure

1. Complete the application changes.
2. Run the relevant tests locally.
3. Commit and push the changes to `main`.
4. Open the repository's GitHub Actions page.
5. Monitor the workflow:
   - Application validation jobs
   - Image publishing
   - Staging deployment
6. Confirm that all jobs complete successfully.

A successful staging deployment means the SSM deployment command completed and all five application rollouts passed.

### Verify the deployed version

Check the GitHub Actions run and its commit SHA.

The deployed image tag should match the intended Git commit SHA.

The staging Kustomize configuration is maintained at:

`k8s/overlays/staging/kustomization.yaml`

Its five application image tags should be kept aligned with the intended staging version.

**Note:** The current deployment workflow updates Kubernetes images directly using `kubectl set image`. It does not automatically update the Kustomize overlay file.

## 6. Accessing the Kubernetes Cluster

The K3s API is accessed locally through AWS Systems Manager port forwarding. This avoids exposing the Kubernetes API port publicly.

### Prerequisites

- AWS CLI installed.
- Session Manager plugin installed.
- Working AWS credentials with permission to start SSM sessions.
- Valid local K3s kubeconfig.

### Start the SSM tunnel

Open a dedicated terminal and run:

```bash
aws ssm start-session \
  --target i-0e0e926b0826c278a \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["127.0.0.1"],"portNumber":["6443"],"localPortNumber":["16443"]}' \
  --profile glitchmob \
  --region ap-southeast-2
```

Keep this terminal open while using Kubernetes locally.

The tunnel forwards local port `16443` to the K3s API on the EC2 instance.

### Kubeconfig configuration

The local kubeconfig is normally stored at:

`~/.kube/config`

Its cluster server endpoint should be:

`https://127.0.0.1:16443`

The kubeconfig must contain valid CA and client certificate credentials.

Do not disable TLS certificate verification or expose private key material.

### Verify cluster connectivity

Open another terminal:

```bash
kubectl config current-context
kubectl get nodes
kubectl get deployments -n staging
kubectl get pods -n staging
```

Expected results:

- The K3s node should be `Ready`.
- All five application deployments should be available.
- Application and supporting pods should be `Running` and `Ready`.

## 7. Staging Environment Verification

### Check deployments

```bash
kubectl get deployments -n staging
```

### Check pods

```bash
kubectl get pods -n staging -o wide
```

### Check services

```bash
kubectl get services -n staging
```

### Inspect a deployment

```bash
kubectl describe deployment web -n staging
```

Replace `web` with the deployment name being investigated.

### Check rollout status

```bash
kubectl rollout status deployment/web \
  -n staging \
  --timeout=300s
```

Repeat for the other application deployments when required.

### Inspect recent events

```bash
kubectl get events -n staging \
  --sort-by=.metadata.creationTimestamp
```

### Check container logs

```bash
kubectl logs deployment/web -n staging \
  --tail=100
```

For another service, replace `web` with its deployment name.

### Verify frontend availability

The frontend is exposed through NodePort `30080`.

Inspect the service:

```bash
kubectl get service -n staging
```

Use the current EC2 public IP and the configured NodePort to test frontend access:

```bash
curl -I http://<EC2-PUBLIC-IP>:30080/
```

An HTTP response confirms that the frontend endpoint is responding. Application-specific functionality should also be checked through the browser.

## 8. Troubleshooting

### GitHub Actions validation failure

**Possible causes:**
- Linting or formatting errors.
- Failed application tests.
- Build errors.
- Dependency installation failures.

**Actions:**
1. Open the failed job in GitHub Actions.
2. Identify the failing command.
3. Reproduce the issue locally.
4. Correct the application code.
5. Run the relevant tests again.
6. Push a corrected commit.

### Docker image publishing failure

**Possible causes:**
- OIDC role assumption failure.
- Incorrect AWS repository configuration.
- ECR authentication failure.
- Docker build failure.

**Actions:**
1. Inspect the `publish-images` job.
2. Verify the GitHub repository variables.
3. Check the IAM role trust and permissions.
4. Verify the ECR repository configuration.
5. Retry after correcting the underlying issue.

### SSM deployment failure

**Possible causes:**
- EC2 instance is not reachable through SSM.
- SSM agent is offline.
- EC2 deployment repository contains uncommitted changes.
- Git fetch or checkout failed.
- Kubernetes rollout timed out.
- Image pull failed.

**Actions:**
1. Inspect the `deploy-staging` job.
2. Identify the SSM command ID in the workflow logs.
3. Check the SSM command output and error output.
4. Verify EC2 SSM connectivity.
5. Inspect the Kubernetes deployment and pod events.
6. Correct the underlying issue before attempting another deployment.

### Pod not starting

Inspect the affected pod:

```bash
kubectl describe pod <POD-NAME> -n staging
```

Inspect its logs:

```bash
kubectl logs <POD-NAME> -n staging \
  --all-containers=true \
  --tail=100
```

Check namespace events:

```bash
kubectl get events -n staging \
  --sort-by=.metadata.creationTimestamp
```

Investigate image pull errors, configuration problems, resource constraints, and application startup failures.

### Local kubectl connection failure

If local Kubernetes commands cannot connect:

1. Confirm that the SSM tunnel is still running.
2. Check the local port:

```bash
curl -k -sS -o /dev/null \
  -w "K3s API HTTP %{http_code}\n" \
  https://127.0.0.1:16443/version
```

3. Verify the kubeconfig server endpoint:

```bash
kubectl config view --minify
```

4. Check that the kubeconfig contains valid client credentials and CA data.

An HTTP 401 response from the unauthenticated curl test can indicate that the API is reachable but requires authentication. Use `kubectl` to verify authenticated access.

If credentials are no longer accepted, retrieve a fresh kubeconfig securely through SSM rather than disabling TLS verification or replacing credentials blindly.

## 9. Deployment Recovery

The current CI/CD workflow does not perform automatic rollback.

If a newly deployed application version is unhealthy:

1. Identify the affected deployment.
2. Inspect its rollout status, pod events, and application logs.
3. Identify a previously successful image tag from GitHub Actions and ECR.
4. Confirm that the previous image exists in ECR.
5. Coordinate the recovery and select the intended previous version.
6. Update the affected deployment to that image:

```bash
kubectl set image deployment/<DEPLOYMENT-NAME> \
  <CONTAINER-NAME>=<ECR-IMAGE-URI>:<PREVIOUS-COMMIT-SHA> \
  -n staging
```

7. Wait for the rollout:

```bash
kubectl rollout status deployment/<DEPLOYMENT-NAME> \
  -n staging \
  --timeout=300s
```

8. Verify the deployment, pods, logs, and application functionality.
9. Record the recovery and reconcile the staging Kustomize image tag with the deployed version.

For a multi-service release, verify compatibility before rolling back individual services. Do not assume that reverting one service is sufficient to restore the complete application.

## 10. Operational Safety

- Do not expose the K3s API publicly.
- Do not expose PostgreSQL or Redis publicly.
- Use SSM for remote EC2 access and deployment.
- Preserve AWS OIDC authentication for GitHub Actions.
- Do not commit AWS credentials, kubeconfig files, private keys, or other secrets.
- Verify image tags before changing staging deployments.
- Inspect Kubernetes events and logs before making recovery changes.
- Avoid applying an outdated Kustomize overlay without reviewing the rendered manifests and intended changes.
- Keep the EC2 deployment repository clean because the deployment workflow refuses to proceed when uncommitted changes are detected.

## 11. Current Verified Deployment

The following deployment was verified on 23 November 2026:

| Item | Verified value |
|---|---|
| AWS region | ap-southeast-2 |
| EC2 instance | i-0e0e926b0826c278a |
| K3s version | v1.37.2+k3s1 |
| Kubernetes node | ip-172-31-37-116 |
| Namespace | staging |
| Application deployments | 5 |
| Application and supporting pods | 7 |
| Deployed application image tag | cdbf4c91a9fb51a1c07252aa35c1e2a5040e50e2 |

All five application deployments were available, and all seven application and supporting pods were running and ready during verification.

This section records a verified deployment snapshot, not a guarantee of current availability.
