# Dhaba DevOps Platform

An end-to-end DevOps engineering portfolio project that takes a
microservices-based restaurant ordering application from source code
to containerized, continuously delivered and monitored Kubernetes
environments.

## Project

Dhaba DevOps Platform demonstrates the design, implementation,
deployment and operation of a Kubernetes-based microservices
platform using modern DevOps practices.
The platform demonstrates automated testing, containerization,
AWS image publishing, Kubernetes orchestration, continuous delivery,
persistent storage, monitoring, incident response and rollback.

## Application Services

| Service | Technology | Responsibility |
|---|---|---|
| web | React / Vite / Nginx | Ordering interface, kitchen screen and statistics |
| menu-api | Python / FastAPI | Menu management and caching |
| orders-api | Go | Order processing |
| kitchen-worker | Java / Spring Boot | Background order processing |
| stats-api | PHP / Laravel | Restaurant statistics |
| postgres | PostgreSQL | Persistent application data |
| redis | Redis | Cache and background job queue |

An additional `ops-monitor` image runs operational monitoring scripts.

## Technology Stack

- Linux and Bash
- Git and GitHub
- Docker and Docker Compose
- AWS EC2 and Elastic Container Registry (ECR)
- Kubernetes and Kustomize
- GitHub Actions
- PostgreSQL and Redis
- Python, Go, Java, PHP and JavaScript
- ShellCheck, Hadolint, Trivy and other testing tools
- Prometheus and Grafana where applicable
- Slack notifications
- Jira project tracking

## Platform Architecture

The intended platform includes:

- Separate staging and production Kubernetes namespaces
- Container images tagged with Git commit SHAs
- Automated CI checks and unit tests
- AWS ECR image publishing
- Automated staging deployments
- Controlled production releases
- Kubernetes persistent volumes for PostgreSQL and Redis
- Deployment rollback and smoke testing
- Shell-based cluster, service and database monitoring
- Slack alerts for failures, recovery and deployments

## Repository Structure

```text
.
├── .github/workflows/
├── db/
├── dev/
├── k8s/
│   ├── base/
│   ├── overlays/
│   │   ├── staging/
│   │   └── production/
│   └── ops/
├── kitchen-worker/
├── menu-api/
├── ops-monitor/
├── orders-api/
├── scripts/
│   └── monitor/
├── stats-api/
└── web/
```

## Project Status

The application source code and initial infrastructure
configurations are prepared.

Infrastructure provisioning, pipeline implementation,
deployment validation and monitoring will be documented
as the project progresses.

## Security Principles

- No AWS access keys or private credentials in Git.
- GitHub Actions should use short-lived AWS credentials through OIDC
  where supported.
- Kubernetes credentials remain outside the repository.
- Application passwords and webhook URLs are stored as secrets.
- Production changes should follow the documented delivery workflow.

## License

To be decided.
