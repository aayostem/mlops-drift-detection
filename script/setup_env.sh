#!/bin/bash

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          MLOps Drift Detection Platform Setup               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check Python version
echo "Checking Python version..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
if [[ $PYTHON_VERSION =~ ^3\.(9|10|11) ]]; then
    print_status "Python $PYTHON_VERSION detected"
else
    print_error "Python 3.9, 3.10, or 3.11 is required"
    exit 1
fi

# Check Docker
echo "Checking Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    print_status "Docker $DOCKER_VERSION detected"
else
    print_warning "Docker not found. Some features may not work."
fi

# Check Docker Compose
echo "Checking Docker Compose..."
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}' | tr -d ',')
    print_status "Docker Compose $DOCKER_COMPOSE_VERSION detected"
else
    print_warning "Docker Compose not found. Using docker compose plugin..."
    if docker compose version &> /dev/null; then
        print_status "Docker Compose plugin available"
    else
        print_error "Neither docker-compose nor docker compose plugin found"
        exit 1
    fi
fi

# Create virtual environment
echo "Setting up virtual environment..."
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
    print_status "Virtual environment created"
else
    print_status "Virtual environment already exists"
fi

# Activate virtual environment
source .venv/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip setuptools wheel

# Install project
echo "Installing project..."
pip install -e ".[dev,security,monitoring]"

# Install pre-commit hooks
echo "Installing pre-commit hooks..."
pre-commit install
pre-commit install --hook-type commit-msg

# Create directories
echo "Creating directories..."
mkdir -p mlruns artifacts logs data/{raw,processed} models/{train,serve} notebooks test-results reports

# Initialize environment
if [ ! -f ".env" ]; then
    echo "Creating .env file..."
    cp .env.example .env
    print_status ".env file created"
    print_warning "Please update .env file with your configuration"
else
    print_status ".env file already exists"
fi

# Create .gitignore if not exists
if [ ! -f ".gitignore" ]; then
    echo "Creating .gitignore..."
    cat > .gitignore << EOF
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual Environment
.venv/
env/
venv/
ENV/
env.bak/
venv.bak/

# MLflow
mlruns/
artifacts/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Testing
.coverage
coverage.xml
*.cover
htmlcov/
.pytest_cache/

# Logs
*.log
logs/

# Jupyter
.ipynb_checkpoints

# Docker
.dockerignore
docker-compose.override.yml

# Security
*.pem
*.key
*.crt

# Temporary files
*.tmp
*.temp

# Local development
local.env
*.local
EOF
    print_status ".gitignore created"
fi

# Create initial MLflow database
if [ ! -f "mlruns/mlflow.db" ]; then
    touch mlruns/mlflow.db
    print_status "MLflow database initialized"
fi

# Test installation
echo "Testing installation..."
python -c "
import prefect, mlflow, sklearn, pandas, fastapi, pydantic, evidently
print('✓ All core imports successful')
"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! 🎉                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "1. Update your .env file:"
echo "   ${YELLOW}nano .env${NC} (or your preferred editor)"
echo ""
echo "2. Start the services:"
echo "   ${YELLOW}make docker-up${NC}"
echo ""
echo "3. Test the setup:"
echo "   ${YELLOW}make health${NC}"
echo ""
echo "4. Run a training pipeline:"
echo "   ${YELLOW}make train${NC}"
echo ""
echo "Useful commands:"
echo "  ${YELLOW}make help${NC}          - Show all available commands"
echo "  ${YELLOW}make docker-up${NC}     - Start all Docker services"
echo "  ${YELLOW}make api${NC}           - Start API server locally"
echo "  ${YELLOW}make test${NC}          - Run tests"
echo "  ${YELLOW}make lint${NC}          - Lint code"
echo "  ${YELLOW}make format${NC}        - Format code"
echo ""
echo "Service URLs (after make docker-up):"
echo "  MLflow:        http://localhost:5000"
echo "  Prefect:       http://localhost:4200"
echo "  API:           http://localhost:8000"
echo "  Monitoring:    http://localhost:8501"
echo "  API Docs:      http://localhost:8000/docs"
echo "  Grafana:       http://localhost:3000"
echo "  Flower:        http://localhost:5555"
echo ""
echo "Happy coding! 🚀"
