# Dhaba DevOps Platform

An end-to-end DevOps portfolio project demonstrating how a microservices-based restaurant ordering application is containerized, tested, deployed to Kubernetes on AWS, and monitored.

## Project Overview

The platform combines application development with practical DevOps engineering:
- Automated CI checks using GitHub Actions.
- Docker image builds and publishing to Amazon ECR.
- AWS authentication through GitHub Actions OIDC.
- Remote deployment to an EC2-hosted K3s cluster using AWS Systems Manager.
- Kubernetes workload management and persistent application storage.
- Infrastructure monitoring with Node Exporter, Prometheus, and Grafana.

## Application Services

| Service | Technology | Responsibility |
|---|---|---|
| web | React / Vite / Nginx | Restaurant frontend |
| menu-api | Python / FastAPI | Menu management |
| orders-api | Go | Order processing |
| kitchen-worker | Java / Spring Boot | Background order processing |
| stats-api | PHP / Laravel | Restaurant statistics |
| postgres | PostgreSQL | Persistent application data |
| redis | Redis | Caching and background job support |

The repository also builds an `ops-monitor` image for operational monitoring scripts. It is not part of the five-service application deployment.

## Technology Stack

- Linux and Bash
- Git and GitHub
- Docker and Docker Compose
- GitHub Actions
- AWS EC2, ECR, IAM OIDC, and Systems Manager
- Kubernetes (K3s) and Kustomize
- PostgreSQL and Redis
- Prometheus and Node Exporter
- Grafana

## CI/CD Pipeline

The GitHub Actions workflow performs the following:

1. Runs CI checks for the five application services.
2. Builds and publishes six Docker images to Amazon ECR.
3. Authenticates to AWS using GitHub OIDC short-lived credentials.
4. Uses AWS Systems Manager to execute the deployment on the EC2 instance.
5. Updates the five application Deployments to the commit-specific image tag.
6. Waits for Kubernetes rollout completion.

Images are tagged with the Git commit SHA to make deployed versions traceable.

The deployment targets the `staging` namespace of the EC2-hosted K3s cluster.

## Staging Environment

- Kubernetes distribution: K3s
- Hosting: AWS EC2
- Namespace: `staging`
- Frontend access: NodePort `30080`
- Backend services: internal Kubernetes networking
- PostgreSQL and Redis: private cluster services

Frontend URL:

`http://54.206.106.165:30080/`

The frontend health endpoint is:

`http://54.206.106.165:30080/health`

## Monitoring

Infrastructure monitoring uses:
- Node Exporter on the EC2 instance.
- Prometheus running on the local Ubuntu machine.
- Grafana running locally.
- SSH tunnelling to access the EC2 Node Exporter securely.

The Grafana dashboard contains infrastructure monitoring panels for the Dhaba environment.

**Dashboard:** Dhaba Infrastructure Monitoring Dashboard

Dashboard configuration:

`monitoring/grafana/dhaba-infrastructure-dashboard.json`

Dashboard screenshot:

![Dhaba Infrastructure Monitoring Dashboard](monitoring/grafana/dashboard-screenshot.png)

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Deployment and Operations Runbook](docs/DEPLOYMENT-RUNBOOK.md)

## Verified Project Status

The latest successful deployment used commit:

`cdbf4c91a9fb51a1c07252aa35c1e2a5040e50e2`

The deployment was verified through AWS Systems Manager and Kubernetes:
- All five application Deployments were ready.
- All seven application and data-service pods were running.
- Application containers used the expected commit-specific image tag.
- The frontend health endpoint returned HTTP 200.

These checks describe the verified deployment at the time of the recorded validation.

## Security Practices

- GitHub Actions uses OIDC for short-lived AWS credentials.
- No long-lived AWS access keys are stored in the repository.
- AWS Systems Manager is used for remote deployment.
- Backend, database, and Redis services are not exposed through public NodePorts.
- Node Exporter monitoring access uses an SSH tunnel.
- Kubernetes and application credentials are kept outside source control.

## License

To be decided.
