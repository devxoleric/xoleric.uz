#!/bin/bash

# System cleanup script
set -e

echo "🧹 Starting system cleanup..."

# Clean Docker
echo "Cleaning Docker..."
docker system prune -f
docker volume prune -f

# Clean old backups (keep last 7 days)
echo "Cleaning old backups..."
find /opt/xoleric/backup -name "*.sql.gz" -mtime +7 -delete
find /opt/xoleric/backup -name "*.tar.gz" -mtime +7 -delete
find /opt/xoleric/backup -name "*.txt" -mtime +30 -delete

# Clean logs
echo "Cleaning old logs..."
find /opt/xoleric/logs -name "*.log.*" -mtime +30 -delete
find /var/log -name "*.gz" -mtime +30 -delete
find /var/log -name "*.1" -mtime +30 -delete

# Clean temporary files
echo "Cleaning temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean package cache
if command -v apt-get &> /dev/null; then
    apt-get clean
    apt-get autoremove -y
fi

if command -v yum &> /dev/null; then
    yum clean all
fi

# Clean Docker images
echo "Cleaning unused Docker images..."
IMAGES_TO_REMOVE=$(docker images --filter "dangling=true" -q)
if [ ! -z "$IMAGES_TO_REMOVE" ]; then
    docker rmi $IMAGES_TO_REMOVE
fi

# Clean old containers
echo "Cleaning stopped containers..."
docker ps -aq --filter "status=exited" | xargs docker rm

# Check disk usage
echo "Checking disk usage..."
df -h /

# Update package list
if command -v apt-get &> /dev/null; then
    apt-get update
fi

echo "✅ Cleanup completed!"
