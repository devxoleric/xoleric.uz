#!/bin/bash

# Xoleric Deployment Script
set -e

echo "🚀 Starting Xoleric deployment..."

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print colored output
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    print_message "Checking dependencies..."
    
    command -v docker >/dev/null 2>&1 || {
        print_error "Docker is not installed"
        exit 1
    }
    
    command -v docker-compose >/dev/null 2>&1 || {
        print_error "Docker Compose is not installed"
        exit 1
    }
    
    command -v node >/dev/null 2>&1 || {
        print_error "Node.js is not installed"
        exit 1
    }
    
    print_message "All dependencies are installed"
}

# Build and push Docker images
build_images() {
    print_message "Building Docker images..."
    
    # Build frontend
    print_message "Building frontend..."
    docker build -t xoleric/frontend:latest -f frontend/Dockerfile.frontend ./frontend
    
    # Build backend
    print_message "Building backend..."
    docker build -t xoleric/backend:latest -f backend/Dockerfile.backend ./backend
    
    # Tag and push if registry is provided
    if [ ! -z "$DOCKER_REGISTRY" ]; then
        print_message "Pushing images to registry..."
        docker tag xoleric/frontend:latest $DOCKER_REGISTRY/xoleric-frontend:latest
        docker tag xoleric/backend:latest $DOCKER_REGISTRY/xoleric-backend:latest
        
        docker push $DOCKER_REGISTRY/xoleric-frontend:latest
        docker push $DOCKER_REGISTRY/xoleric-backend:latest
    fi
}

# Run database migrations
run_migrations() {
    print_message "Running database migrations..."
    
    # Connect to PostgreSQL and run migrations
    docker-compose exec postgres psql -U xoleric -d xoleric -f /docker-entrypoint-initdb.d/migrations.sql
    
    # Run Supabase migrations
    if [ ! -z "$SUPABASE_URL" ]; then
        print_message "Running Supabase migrations..."
        # Use Supabase CLI or direct SQL
    fi
}

# Deploy services
deploy_services() {
    print_message "Deploying services..."
    
    # Stop existing services
    docker-compose down
    
    # Pull latest images
    if [ ! -z "$DOCKER_REGISTRY" ]; then
        docker-compose pull
    fi
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be healthy
    print_message "Waiting for services to be healthy..."
    sleep 30
    
    # Check service health
    check_service_health
}

# Check service health
check_service_health() {
    print_message "Checking service health..."
    
    # Check frontend
    if curl -s -f http://localhost:3000/health > /dev/null; then
        print_message "Frontend is healthy"
    else
        print_error "Frontend health check failed"
        exit 1
    fi
    
    # Check backend
    if curl -s -f http://localhost:5000/health > /dev/null; then
        print_message "Backend is healthy"
    else
        print_error "Backend health check failed"
        exit 1
    fi
    
    # Check database
    if docker-compose exec postgres pg_isready -U xoleric > /dev/null; then
        print_message "Database is healthy"
    else
        print_error "Database health check failed"
        exit 1
    fi
}

# Setup SSL certificates
setup_ssl() {
    if [ "$ENVIRONMENT" = "production" ]; then
        print_message "Setting up SSL certificates..."
        
        # Create SSL directory
        mkdir -p ssl
        
        # Generate self-signed certificates for development
        if [ ! -f ssl/xoleric.key ] || [ ! -f ssl/xoleric.crt ]; then
            print_warning "Generating self-signed SSL certificates..."
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout ssl/xoleric.key \
                -out ssl/xoleric.crt \
                -subj "/C=UZ/ST=Tashkent/L=Tashkent/O=Xoleric/CN=xoleric.uz"
        fi
        
        # For production, you should use Let's Encrypt
        if [ "$USE_LETSENCRYPT" = "true" ]; then
            print_message "Setting up Let's Encrypt certificates..."
            # Add certbot commands here
        fi
    fi
}

# Backup database
backup_database() {
    print_message "Creating database backup..."
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="backup/xoleric_backup_$TIMESTAMP.sql"
    
    mkdir -p backup
    
    # Backup PostgreSQL
    docker-compose exec postgres pg_dump -U xoleric xoleric > $BACKUP_FILE
    
    # Compress backup
    gzip $BACKUP_FILE
    
    # Upload to cloud storage if configured
    if [ ! -z "$BACKUP_BUCKET" ]; then
        print_message "Uploading backup to cloud storage..."
        # Add cloud storage upload commands here
    fi
    
    # Clean old backups (keep last 7 days)
    find backup -name "*.sql.gz" -mtime +7 -delete
    
    print_message "Database backup completed: ${BACKUP_FILE}.gz"
}

# Main deployment process
main() {
    print_message "Starting Xoleric deployment process"
    
    # Check dependencies
    check_dependencies
    
    # Setup SSL
    setup_ssl
    
    # Backup database (for production)
    if [ "$ENVIRONMENT" = "production" ]; then
        backup_database
    fi
    
    # Build images
    build_images
    
    # Deploy services
    deploy_services
    
    # Run migrations
    run_migrations
    
    print_message "✅ Deployment completed successfully!"
    
    # Show deployment info
    echo ""
    echo "================ DEPLOYMENT INFO ================"
    echo "Frontend URL: https://xoleric.uz"
    echo "Backend API: https://api.xoleric.uz"
    echo "WebSocket: wss://ws.xoleric.uz"
    echo "Admin Panel: https://xoleric.uz/admin"
    echo "Grafana: https://monitor.xoleric.uz"
    echo "================================================"
}

# Run main function
main "$@"
