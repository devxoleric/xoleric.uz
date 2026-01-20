#!/bin/bash

# Docker container health check script
set -e

echo "🩺 Starting health checks..."

# Check if containers are running
containers=(
    "xoleric-frontend"
    "xoleric-backend"
    "xoleric-postgres"
    "xoleric-redis"
    "xoleric-traefik"
)

for container in "${containers[@]}"; do
    if docker ps --filter "name=$container" --filter "status=running" | grep -q "$container"; then
        echo "✅ $container is running"
    else
        echo "❌ $container is not running!"
        exit 1
    fi
done

# Check frontend health
echo "Checking frontend health..."
if curl -s -f http://localhost:3000/health > /dev/null; then
    echo "✅ Frontend is healthy"
else
    echo "❌ Frontend health check failed"
    exit 1
fi

# Check backend health
echo "Checking backend health..."
if curl -s -f http://localhost:5000/health > /dev/null; then
    echo "✅ Backend is healthy"
else
    echo "❌ Backend health check failed"
    exit 1
fi

# Check database connection
echo "Checking database connection..."
if docker exec xoleric-postgres pg_isready -U $DB_USER > /dev/null; then
    echo "✅ Database is healthy"
else
    echo "❌ Database health check failed"
    exit 1
fi

# Check Redis
echo "Checking Redis..."
if docker exec xoleric-redis redis-cli ping | grep -q "PONG"; then
    echo "✅ Redis is healthy"
else
    echo "❌ Redis health check failed"
    exit 1
fi

# Check disk space
echo "Checking disk space..."
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -lt 90 ]; then
    echo "✅ Disk space: ${DISK_USAGE}% used"
else
    echo "⚠️  Warning: Disk space at ${DISK_USAGE}%"
fi

# Check memory usage
echo "Checking memory usage..."
MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2*100}')
if [ $MEM_USAGE -lt 80 ]; then
    echo "✅ Memory usage: ${MEM_USAGE}%"
else
    echo "⚠️  Warning: Memory usage at ${MEM_USAGE}%"
fi

# Check SSL certificates
echo "Checking SSL certificates..."
if [ -f "/etc/nginx/ssl/xoleric.net.crt" ]; then
    CERT_EXPIRE=$(openssl x509 -in /etc/nginx/ssl/xoleric.net.crt -enddate -noout | cut -d= -f2)
    DAYS_LEFT=$(( ($(date -d "$CERT_EXPIRE" +%s) - $(date +%s)) / 86400 ))
    
    if [ $DAYS_LEFT -gt 30 ]; then
        echo "✅ SSL certificate expires in $DAYS_LEFT days"
    elif [ $DAYS_LEFT -gt 7 ]; then
        echo "⚠️  SSL certificate expires in $DAYS_LEFT days"
    else
        echo "❌ SSL certificate expires in $DAYS_LEFT days!"
        exit 1
    fi
else
    echo "⚠️  SSL certificate not found"
fi

echo "🎉 All health checks passed!"
