.PHONY: help setup install install-dev venv clean test lint format type-check security docker-up docker-down compose-build compose-down api mlflow dashboard prefect train monitor deploy docs notebook health check-all ci cd clean-all docker-logs docker-restart pre-commit-run pre-commit-install init-env init-dirs test-unit test-integration test-e2e test-cov format-check docs-serve build-package publish-test publish-prod db-init db-migrate db-upgrade db-downgrade logs metrics version shell activate requirements git-hooks profile benchmark backup banner

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Variables
PYTHON := python3
PIP := pip3
PROJECT_NAME := mlops-drift-detection
VENV := .venv
PYTHON_VENV := $(VENV)/bin/python
PIP_VENV := $(VENV)/bin/pip
DOCKER_COMPOSE := docker-compose -f infrastructure/docker-compose.yml
PRE_COMMIT := pre-commit
RUFF := ruff
BLACK := black
MYPY := mypy
PYTEST := pytest

# Detect OS
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    OPEN := xdg-open
else ifeq ($(UNAME_S),Darwin)
    OPEN := open
else
    OPEN := start
endif

# Default target
.DEFAULT_GOAL := help

help: ## 📖 Display this help message
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║              MLOps Drift Detection Platform                 ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  $(GREEN)make setup$(NC)        Set up development environment"
	@echo "  $(GREEN)make docker-up$(NC)    Start all services"
	@echo "  $(GREEN)make train$(NC)        Run training pipeline"
	@echo "  $(GREEN)make api$(NC)          Start API server"
	@echo ""
	@echo "Service URLs:"
	@echo "  MLflow:        http://localhost:5000"
	@echo "  Prefect:       http://localhost:4200"
	@echo "  API:           http://localhost:8000"
	@echo "  Monitoring:    http://localhost:8501"
	@echo "  API Docs:      http://localhost:8000/docs"

# Environment Setup
setup: venv install-dev pre-commit-install init-env init-dirs ## 🚀 Complete development environment setup
	@echo "$(GREEN)✓ Development environment setup complete!$(NC)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Update .env file with your configuration"
	@echo "  2. Start services: $(GREEN)make docker-up$(NC)"
	@echo "  3. Test installation: $(GREEN)make health$(NC)"

venv: ## 🐍 Create Python virtual environment
	@if [ ! -d "$(VENV)" ]; then \
		echo "$(YELLOW)Creating virtual environment...$(NC)"; \
		$(PYTHON) -m venv $(VENV); \
		echo "$(GREEN)✓ Virtual environment created$(NC)"; \
	else \
		echo "$(GREEN)✓ Virtual environment already exists$(NC)"; \
	fi

install: venv ## 📦 Install production dependencies
	@echo "$(YELLOW)Installing production dependencies...$(NC)"
	@$(PIP_VENV) install -e ".[docker]"
	@echo "$(GREEN)✓ Production dependencies installed$(NC)"

install-dev: venv ## 🔧 Install development dependencies
	@echo "$(YELLOW)Installing development dependencies...$(NC)"
	@$(PIP_VENV) install -e ".[dev,security,monitoring]"
	@echo "$(GREEN)✓ Development dependencies installed$(NC)"

pre-commit-install: ## 🔒 Install pre-commit hooks
	@echo "$(YELLOW)Installing pre-commit hooks...$(NC)"
	@$(PRE_COMMIT) install
	@$(PRE_COMMIT) install --hook-type commit-msg
	@echo "$(GREEN)✓ Pre-commit hooks installed$(NC)"

init-env: ## ⚙️ Initialize environment configuration
	@if [ ! -f ".env" ]; then \
		echo "$(YELLOW)Creating .env file from template...$(NC)"; \
		cp .env.example .env; \
		echo "$(GREEN)✓ .env file created$(NC)"; \
		echo "$(YELLOW)Please update .env file with your configuration$(NC)"; \
	else \
		echo "$(GREEN)✓ .env file already exists$(NC)"; \
	fi

init-dirs: ## 📁 Initialize required directories
	@echo "$(YELLOW)Creating required directories...$(NC)"
	@mkdir -p mlruns artifacts logs data/{raw,processed} models/{train,serve} notebooks test-results reports
	@echo "$(GREEN)✓ Directories created$(NC)"

# Testing
test: venv ## 🧪 Run all tests
	@echo "$(YELLOW)Running tests...$(NC)"
	@$(PYTHON_VENV) -m $(PYTEST) \
		--tb=short \
		--color=yes \
		--junitxml=test-results/junit.xml \
		--html=test-results/report.html \
		--self-contained-html
	@echo "$(GREEN)✓ Tests completed$(NC)"

test-unit: venv ## 🧪 Run unit tests only
	@echo "$(YELLOW)Running unit tests...$(NC)"
	@$(PYTHON_VENV) -m $(PYTEST) -m "unit" -v

test-integration: venv ## 🔗 Run integration tests
	@echo "$(YELLOW)Running integration tests...$(NC)"
	@$(PYTHON_VENV) -m $(PYTEST) -m "integration" -v

test-e2e: venv ## 🧪 Run end-to-end tests
	@echo "$(YELLOW)Running end-to-end tests...$(NC)"
	@$(PYTHON_VENV) -m $(PYTEST) -m "e2e" -v

test-cov: venv ## 📊 Run tests with coverage report
	@echo "$(YELLOW)Running tests with coverage...$(NC)"
	@$(PYTHON_VENV) -m $(PYTEST) --cov=src --cov-report=html --cov-report=term

# Code Quality
lint: venv ## 🔍 Lint code with ruff
	@echo "$(YELLOW)Linting code with ruff...$(NC)"
	@$(PYTHON_VENV) -m $(RUFF) check src/ tests/
	@echo "$(GREEN)✓ Linting completed$(NC)"

format: venv ## 🎨 Format code with black and ruff
	@echo "$(YELLOW)Formatting code...$(NC)"
	@$(PYTHON_VENV) -m $(BLACK) src/ tests/
	@$(PYTHON_VENV) -m $(RUFF) format src/ tests/
	@echo "$(GREEN)✓ Formatting completed$(NC)"

format-check: venv ## ✅ Check code formatting
	@echo "$(YELLOW)Checking code formatting...$(NC)"
	@$(PYTHON_VENV) -m $(BLACK) --check src/ tests/
	@$(PYTHON_VENV) -m $(RUFF) format --check src/ tests/
	@echo "$(GREEN)✓ Formatting check passed$(NC)"

type-check: venv ## 📝 Run type checking with mypy
	@echo "$(YELLOW)Running type checking...$(NC)"
	@$(PYTHON_VENV) -m $(MYPY) src/
	@echo "$(GREEN)✓ Type checking completed$(NC)"

security: venv ## 🔒 Run security checks
	@echo "$(YELLOW)Running security checks...$(NC)"
	@$(PYTHON_VENV) -m bandit -r src/ -f json -o security-report.json
	@$(PYTHON_VENV) -m safety check --json > safety-report.json
	@echo "$(GREEN)✓ Security checks completed$(NC)"

pre-commit-run: venv ## 🚀 Run all pre-commit hooks
	@echo "$(YELLOW)Running pre-commit hooks...$(NC)"
	@$(PRE_COMMIT) run --all-files
	@echo "$(GREEN)✓ Pre-commit hooks completed$(NC)"

# Docker Services
docker-up: ## 🐳 Start all Docker services
	@echo "$(YELLOW)Starting Docker services...$(NC)"
	@$(DOCKER_COMPOSE) up -d --build
	@echo "$(GREEN)✓ Docker services started$(NC)"
	@echo ""
	@echo "$(BLUE)Service URLs:$(NC)"
	@echo "  MLflow:        http://localhost:5000"
	@echo "  Prefect:       http://localhost:4200"
	@echo "  API:           http://localhost:8000"
	@echo "  Monitoring:    http://localhost:8501"
	@echo "  API Docs:      http://localhost:8000/docs"

docker-down: ## 🐳 Stop all Docker services
	@echo "$(YELLOW)Stopping Docker services...$(NC)"
	@$(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Docker services stopped$(NC)"

docker-logs: ## 📋 Show Docker service logs
	@$(DOCKER_COMPOSE) logs -f --tail=100

docker-restart: ## 🔄 Restart Docker services
	@$(MAKE) docker-down
	@$(MAKE) docker-up

compose-build: ## 🔨 Build Docker images
	@echo "$(YELLOW)Building Docker images...$(NC)"
	@$(DOCKER_COMPOSE) build --no-cache
	@echo "$(GREEN)✓ Docker images built$(NC)"

compose-down: ## 🧹 Remove Docker containers and volumes
	@echo "$(YELLOW)Removing Docker containers and volumes...$(NC)"
	@$(DOCKER_COMPOSE) down -v --remove-orphans
	@echo "$(GREEN)✓ Docker containers and volumes removed$(NC)"

# Service Management
api: venv ## 🚀 Start FastAPI server
	@echo "$(YELLOW)Starting FastAPI server...$(NC)"
	@$(PYTHON_VENV) -m uvicorn src.api.main:app \
		--host 0.0.0.0 \
		--port 8000 \
		--reload \
		--reload-dir src \
		--log-level info

mlflow: venv ## 📊 Start MLflow tracking server
	@echo "$(YELLOW)Starting MLflow server...$(NC)"
	@$(PYTHON_VENV) -m mlflow server \
		--host 0.0.0.0 \
		--port 5000 \
		--backend-store-uri sqlite:///mlruns/mlflow.db \
		--default-artifact-root ./mlruns \
		--gunicorn-opts "--log-level info"

dashboard: venv ## 📈 Start monitoring dashboard
	@echo "$(YELLOW)Starting monitoring dashboard...$(NC)"
	@$(PYTHON_VENV) -m streamlit run src/monitoring/dashboard.py \
		--server.port 8501 \
		--server.address 0.0.0.0 \
		--theme.base light

prefect: venv ## ⚙️ Start Prefect server
	@echo "$(YELLOW)Starting Prefect server...$(NC)"
	@$(PYTHON_VENV) -m prefect server start

# Training & Monitoring
train: venv ## 🤖 Run training pipeline
	@echo "$(YELLOW)Running training pipeline...$(NC)"
	@$(PYTHON_VENV) -c "from src.pipelines.training_pipeline import ml_training_pipeline; ml_training_pipeline()"
	@echo "$(GREEN)✓ Training pipeline completed$(NC)"

train-local: venv ## 🤖 Run training without Prefect
	@echo "$(YELLOW)Running local training...$(NC)"
	@$(PYTHON_VENV) -c "import asyncio; from src.data.pipeline import data_pipeline_flow; from src.models.training import train_and_evaluate_models; result = data_pipeline_flow(); training_result = train_and_evaluate_models(result['X_train'], result['X_test'], result['y_train'], result['y_test'], result['dataset_info']); print(f'Training completed: {training_result[\"best_model_name\"]} - {training_result[\"best_score\"]:.4f}')"

monitor: venv ## 👁️ Run drift monitoring
	@echo "$(YELLOW)Running drift monitoring...$(NC)"
	@$(PYTHON_VENV) -c "from src.monitoring.drift import drift_monitoring_flow; drift_monitoring_flow()"
	@echo "$(GREEN)✓ Drift monitoring completed$(NC)"

# Development Tools
notebook: venv ## 📓 Start Jupyter notebook server
	@echo "$(YELLOW)Starting Jupyter notebook...$(NC)"
	@$(PYTHON_VENV) -m jupyter notebook \
		--ip=0.0.0.0 \
		--port=8888 \
		--no-browser \
		--notebook-dir=notebooks

docs: venv ## 📚 Generate documentation
	@echo "$(YELLOW)Generating documentation...$(NC)"
	@$(PYTHON_VENV) -m pdoc src -o docs/api --force
	@echo "$(GREEN)✓ Documentation generated$(NC)"
	@echo "Open docs/api/index.html to view"

docs-serve: venv ## 🌐 Serve documentation locally
	@echo "$(YELLOW)Serving documentation...$(NC)"
	@$(PYTHON_VENV) -m mkdocs serve

# Health Checks
health: venv ## 🩺 Check health of all services
	@echo "$(YELLOW)Checking service health...$(NC)"
	@echo ""
	@echo "$(BLUE)MLflow:$(NC)"
	@curl -s -f http://localhost:5000/health >/dev/null 2>&1 && \
		echo "$(GREEN)  ✓ Healthy$(NC)" || \
		echo "$(RED)  ✗ Unhealthy$(NC)"
	@echo ""
	@echo "$(BLUE)API:$(NC)"
	@curl -s -f http://localhost:8000/health >/dev/null 2>&1 && \
		echo "$(GREEN)  ✓ Healthy$(NC)" || \
		echo "$(RED)  ✗ Unhealthy$(NC)"
	@echo ""
	@echo "$(BLUE)Prefect:$(NC)"
	@curl -s -f http://localhost:4200/api/health >/dev/null 2>&1 && \
		echo "$(GREEN)  ✓ Healthy$(NC)" || \
		echo "$(RED)  ✗ Unhealthy$(NC)"
	@echo ""
	@echo "$(GREEN)Health check completed$(NC)"

check-all: format-check lint type-check test security ## ✅ Run all checks
	@echo "$(GREEN)✓ All checks passed!$(NC)"

# CI/CD
ci: check-all ## 🔄 Run CI pipeline locally
	@echo "$(GREEN)✓ CI pipeline completed successfully!$(NC)"

cd: test build-package ## 🚀 Run CD pipeline locally
	@echo "$(GREEN)✓ CD pipeline completed successfully!$(NC)"

# Cleanup
clean: ## 🧹 Clean up generated files and caches
	@echo "$(YELLOW)Cleaning up...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name "*.pyo" -delete
	@find . -type f -name ".coverage" -delete
	@find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "build" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".ipynb_checkpoints" -exec rm -rf {} + 2>/dev/null || true
	@rm -rf .coverage coverage.xml htmlcov/ test-results/ reports/ security-report.json safety-report.json profile.prof
	@rm -rf mlruns/* artifacts/* logs/* 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup complete!$(NC)"

clean-all: clean docker-down ## 🧹 Clean everything including Docker
	@echo "$(YELLOW)Removing virtual environment...$(NC)"
	@rm -rf $(VENV)
	@echo "$(GREEN)✓ Complete cleanup done!$(NC)"

# Package Management
build-package: venv ## 📦 Build Python package
	@echo "$(YELLOW)Building package...$(NC)"
	@$(PYTHON_VENV) -m build
	@echo "$(GREEN)✓ Package built$(NC)"

publish-test: build-package ## 📤 Publish to test PyPI
	@echo "$(YELLOW)Publishing to test PyPI...$(NC)"
	@$(PYTHON_VENV) -m twine upload --repository testpypi dist/*

publish-prod: build-package ## 🚀 Publish to PyPI
	@echo "$(YELLOW)Publishing to PyPI...$(NC)"
	@$(PYTHON_VENV) -m twine upload dist/*

# Database
db-init: venv ## 🗄️ Initialize database
	@echo "$(YELLOW)Initializing database...$(NC)"
	@$(PYTHON_VENV) -c "from src.config.settings import settings; print(f'Database: {settings.DATABASE_URL}')"
	@$(PYTHON_VENV) -m alembic upgrade head
	@echo "$(GREEN)✓ Database initialized$(NC)"

db-migrate: venv ## 📝 Create new database migration
	@echo "$(YELLOW)Creating database migration...$(NC)"
	@read -p "Enter migration message: " message; \
	$(PYTHON_VENV) -m alembic revision --autogenerate -m "$$message"

db-upgrade: venv ## ⬆️ Apply database migrations
	@echo "$(YELLOW)Applying database migrations...$(NC)"
	@$(PYTHON_VENV) -m alembic upgrade head
	@echo "$(GREEN)✓ Database migrations applied$(NC)"

db-downgrade: venv ## ⬇️ Rollback database migration
	@echo "$(YELLOW)Rolling back database migration...$(NC)"
	@$(PYTHON_VENV) -m alembic downgrade -1
	@echo "$(GREEN)✓ Database migration rolled back$(NC)"

# Monitoring
logs: ## 📋 Tail application logs
	@tail -f logs/*.log 2>/dev/null || echo "$(YELLOW)No log files found$(NC)"

metrics: ## 📊 Show Prometheus metrics
	@echo "$(YELLOW)Fetching metrics...$(NC)"
	@curl -s http://localhost:8000/metrics | head -50

# Utility
version: venv ## ℹ️ Show current version
	@$(PYTHON_VENV) -c "from src.__version__ import __version__; print(f'Version: {__version__}')"

shell: venv ## 🐚 Open Python shell with project loaded
	@$(PYTHON_VENV) -m IPython --no-banner --no-confirm-exit

activate: ## 🔌 Activate virtual environment
	@echo "Run: source $(VENV)/bin/activate"

requirements: venv ## 📋 Generate requirements files
	@echo "$(YELLOW)Generating requirements files...$(NC)"
	@$(PIP_VENV) freeze > requirements.txt
	@$(PIP_VENV) freeze --exclude-editable | grep -v "^-e" > requirements.lock
	@echo "$(GREEN)✓ Requirements files generated$(NC)"

# Git Hooks
git-hooks: pre-commit-install ## 🔧 Install git hooks
	@echo "$(GREEN)✓ Git hooks installed$(NC)"

# Performance
profile: venv ## ⚡ Profile application performance
	@echo "$(YELLOW)Profiling application...$(NC)"
	@$(PYTHON_VENV) -m cProfile -o profile.prof -m src.api.main
	@echo "$(GREEN)Profile saved to profile.prof$(NC)"

benchmark: venv ## 🏃 Run performance benchmarks
	@echo "$(YELLOW)Running benchmarks...$(NC)"
	@$(PYTHON_VENV) -m locust -f tests/load_test.py --headless -u 100 -r 10 --run-time 1m

# Backup
backup: ## 💾 Backup project data
	@echo "$(YELLOW)Backing up project data...$(NC)"
	@tar -czf backup-$(shell date +%Y%m%d-%H%M%S).tar.gz \
		mlruns/ artifacts/ models/ data/ \
		--exclude="*.log" --exclude="*.pyc"
	@echo "$(GREEN)✓ Backup created$(NC)"

# Print fancy banner
banner: ## 🎉 Print project banner
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║                                                              ║"
	@echo "║  $(GREEN)███╗   ███╗██╗      ██████╗ ██████╗ ███████╗$(NC)                ║"
	@echo "║  $(GREEN)████╗ ████║██║     ██╔═══██╗██╔══██╗██╔════╝$(NC)                ║"
	@echo "║  $(GREEN)██╔████╔██║██║     ██║   ██║██████╔╝███████╗$(NC)                ║"
	@echo "║  $(GREEN)██║╚██╔╝██║██║     ██║   ██║██╔═══╝ ╚════██║$(NC)                ║"
	@echo "║  $(GREEN)██║ ╚═╝ ██║███████╗╚██████╔╝██║     ███████║$(NC)                ║"
	@echo "║  $(GREEN)╚═╝     ╚═╝╚══════╝ ╚═════╝ ╚═╝     ╚══════╝$(NC)                ║"
	@echo "║                                                              ║"
	@echo "║  $(BLUE)Drift Detection Platform$(NC)                                 ║"
	@echo "║                                                              ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"

# Deploy target placeholder (you should implement this based on your deployment strategy)
deploy: ## 🚀 Deploy the application
	@echo "$(YELLOW)Deployment target not implemented. Override this target in your deployment Makefile.$(NC)"
	@echo "Common deployment strategies:"
	@echo "  - Docker Compose: docker-compose -f docker-compose.prod.yml up -d"
	@echo "  - Kubernetes: kubectl apply -f k8s/"
	@echo "  - Cloud: See cloud provider specific commands"

# Helpers
.PHONY: _check_venv
_check_venv:
	@if [ ! -d "$(VENV)" ]; then \
		echo "$(RED)Virtual environment not found. Run 'make setup' first.$(NC)"; \
		exit 1; \
	fi
	