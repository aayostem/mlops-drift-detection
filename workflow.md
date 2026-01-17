# Clone and setup
```bash
git clone https://github.com/your-org/mlops-drift-detection-platform.git
cd mlops-drift-detection-platform
make setup
```
# Development Workflow
```bash
# Start all services
make docker-up

# Run tests
make test

# Lint and format code
make lint
make format

# Check types
make type-check

# Run security checks
make security

# Start API for development
make api

# Start monitoring dashboard
make dashboard
```

# Production Deployment

```bash
# Build and deploy
make build-package
make deploy-prod

# Or use Docker Compose for production
docker-compose -f docker-compose.prod.yml up -d
```
# Monitoring & Debugging
```bash
# Check service health
make health

# View logs
make docker-logs

# View metrics
make metrics

# Run performance benchmarks
make benchmark

```
# Key Features of This Setup

Modern Python Packaging: Uses pyproject.toml with hatch for build system

Complete Development Environment: Single command setup with make setup

Containerized Services: Full Docker Compose stack with PostgreSQL, Redis, MLflow, etc.

Code Quality: Pre-commit hooks with ruff, black, mypy, bandit

Testing: Comprehensive test setup with pytest, coverage, and HTML reports

Type Safety: Full mypy configuration with Pydantic support

Security: Built-in security scanning with bandit and safety

Documentation: Auto-generated API docs with pdoc and mkdocs

Monitoring: Prometheus, Grafana, and structured logging

CI/CD Ready: GitHub Actions workflows included

This setup follows industry best practices and provides a production-ready foundation for your MLOps platform.



