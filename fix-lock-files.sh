#!/bin/bash

# Lock file fix script for Xoleric deployment
set -e

echo "🔧 Fixing lock files..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate fresh lock files
generate_lock_files() {
    local dir=$1
    local use_yarn=$2
    
    echo "Processing $dir..."
    
    cd "$dir" || {
        print_error "Directory $dir not found"
        return 1
    }
    
    # Backup existing lock files
    if [ -f "package-lock.json" ]; then
        cp package-lock.json package-lock.json.backup
        print_success "Backed up package-lock.json"
    fi
    
    if [ -f "yarn.lock" ]; then
        cp yarn.lock yarn.lock.backup
        print_success "Backed up yarn.lock"
    fi
    
    # Remove existing node_modules and lock files
    rm -rf node_modules package-lock.json yarn.lock
    
    # Generate new lock file based on package manager
    if [ "$use_yarn" = "true" ]; then
        if command -v yarn &> /dev/null; then
            yarn install --frozen-lockfile
            print_success "Generated yarn.lock"
        else
            print_error "Yarn not installed, using npm"
            npm ci
            print_success "Generated package-lock.json with npm"
        fi
    else
        npm ci
        print_success "Generated package-lock.json"
    fi
    
    # Verify lock file
    if [ -f "package-lock.json" ]; then
        if jq empty package-lock.json >/dev/null 2>&1; then
            print_success "package-lock.json is valid JSON"
        else
            print_error "package-lock.json is invalid JSON"
            return 1
        fi
    fi
    
    if [ -f "yarn.lock" ]; then
        print_success "yarn.lock generated successfully"
    fi
    
    cd - >/dev/null
}

# Function to fix Docker build cache issues
fix_docker_cache() {
    echo "Fixing Docker cache issues..."
    
    # Clean Docker cache
    docker system prune -f
    
    # Remove dangling images
    docker images -f "dangling=true" -q | xargs -r docker rmi
    
    # Clean build cache
    docker builder prune -f
    
    print_success "Docker cache cleaned"
}

# Function to fix permission issues
fix_permissions() {
    echo "Fixing file permissions..."
    
    # Fix lock file permissions
    find . -name "package-lock.json" -exec chmod 644 {} \;
    find . -name "yarn.lock" -exec chmod 644 {} \;
    
    # Fix node_modules permissions
    find . -name "node_modules" -type d -exec chmod 755 {} \;
    find . -path "*/node_modules/*" -type f -exec chmod 644 {} \;
    
    # Fix uploads directory
    mkdir -p uploads
    chmod 755 uploads
    
    # Fix logs directory
    mkdir -p logs
    chmod 755 logs
    
    print_success "Permissions fixed"
}

# Function to validate dependencies
validate_dependencies() {
    echo "Validating dependencies..."
    
    # Check Node.js version
    NODE_VERSION=$(node -v)
    REQUIRED_VERSION="v18"
    
    if [[ "$NODE_VERSION" != "$REQUIRED_VERSION"* ]]; then
        print_warning "Node.js version $NODE_VERSION found, $REQUIRED_VERSION.x recommended"
    else
        print_success "Node.js version $NODE_VERSION is compatible"
    fi
    
    # Check npm/yarn
    if command -v npm &> /dev/null; then
        NPM_VERSION=$(npm -v)
        print_success "npm $NPM_VERSION installed"
    else
        print_error "npm not installed"
        exit 1
    fi
    
    # Check Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_success "Docker installed: $DOCKER_VERSION"
    else
        print_error "Docker not installed"
        exit 1
    fi
    
    # Check jq for JSON validation
    if ! command -v jq &> /dev/null; then
        print_warning "jq not installed, installing..."
        apk add --no-cache jq 2>/dev/null || apt-get install -y jq 2>/dev/null || yum install -y jq 2>/dev/null
    fi
}

# Function to create deployment lock
create_deployment_lock() {
    echo "Creating deployment lock..."
    
    LOCK_FILE="/tmp/xoleric-deploy.lock"
    
    if [ -f "$LOCK_FILE" ]; then
        print_error "Deployment already in progress (lock file exists)"
        echo "If this is an error, run: rm $LOCK_FILE"
        exit 1
    fi
    
    # Create lock file
    echo "PID: $$" > "$LOCK_FILE"
    echo "Date: $(date)" >> "$LOCK_FILE"
    echo "User: $(whoami)" >> "$LOCK_FILE"
    
    # Set trap to remove lock on exit
    trap 'rm -f "$LOCK_FILE"' EXIT INT TERM
    
    print_success "Deployment lock created"
}

# Main function
main() {
    echo "🚀 Starting lock file fix process..."
    
    # Create deployment lock
    create_deployment_lock
    
    # Validate dependencies
    validate_dependencies
    
    # Fix frontend lock files
    print_success "=== FIXING FRONTEND ==="
    generate_lock_files "frontend" "false"
    
    # Fix backend lock files
    print_success "=== FIXING BACKEND ==="
    generate_lock_files "backend" "false"
    
    # Fix permissions
    fix_permissions
    
    # Fix Docker cache
    fix_docker_cache
    
    # Create consolidated lock file for deployment
    create_consolidated_lock
    
    print_success "✅ Lock file fix process completed!"
    
    # Show summary
    show_summary
}

# Function to create consolidated lock file
create_consolidated_lock() {
    echo "Creating consolidated lock file..."
    
    cat > deploy.lock.json << EOF
{
  "deployment": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "1.0.0",
    "environment": "production"
  },
  "dependencies": {
    "node": "$(node -v)",
    "npm": "$(npm -v)",
    "docker": "$(docker --version | cut -d' ' -f3 | tr -d ',')"
  },
  "checksums": {
    "frontend_package_lock": "$(sha256sum frontend/package-lock.json 2>/dev/null | cut -d' ' -f1 || echo 'not_found')",
    "backend_package_lock": "$(sha256sum backend/package-lock.json 2>/dev/null | cut -d' ' -f1 || echo 'not_found')",
    "docker_compose": "$(sha256sum docker-compose.prod.yml 2>/dev/null | cut -d' ' -f1 || echo 'not_found')"
  },
  "services": {
    "frontend": {
      "status": "ready",
      "port": 3000,
      "health_check": "/health"
    },
    "backend": {
      "status": "ready",
      "port": 5000,
      "health_check": "/health"
    },
    "database": {
      "status": "ready",
      "type": "postgresql",
      "port": 5432
    }
  }
}
EOF
    
    print_success "Created deploy.lock.json"
}

# Function to show summary
show_summary() {
    echo ""
    echo "📊 DEPLOYMENT LOCK FIX SUMMARY"
    echo "=============================="
    
    # Check lock files
    echo "Lock Files:"
    if [ -f "frontend/package-lock.json" ]; then
        FRONTEND_SIZE=$(stat -c%s "frontend/package-lock.json")
        echo "  ✅ frontend/package-lock.json ($((FRONTEND_SIZE/1024)) KB)"
    else
        echo "  ❌ frontend/package-lock.json (missing)"
    fi
    
    if [ -f "backend/package-lock.json" ]; then
        BACKEND_SIZE=$(stat -c%s "backend/package-lock.json")
        echo "  ✅ backend/package-lock.json ($((BACKEND_SIZE/1024)) KB)"
    else
        echo "  ❌ backend/package-lock.json (missing)"
    fi
    
    # Check Docker
    echo ""
    echo "Docker Status:"
    if docker ps &> /dev/null; then
        echo "  ✅ Docker daemon is running"
    else
        echo "  ❌ Docker daemon is not running"
    fi
    
    # Disk space
    echo ""
    echo "Disk Space:"
    df -h / | tail -1 | awk '{print "  💾 " $4 " free out of " $2 " (" $5 " used)"}'
    
    # Memory
    echo ""
    echo "Memory:"
    free -h | awk '/Mem:/ {print "  🧠 " $4 " free out of " $2 " (" $3 " used)"}'
    
    echo ""
    echo "✅ Lock file fix completed successfully!"
    echo "Next steps:"
    echo "1. Run: ./deploy.sh"
    echo "2. Monitor: docker-compose logs -f"
    echo "3. Verify: curl http://localhost:3000/health"
}

# Run main function
main "$@"
