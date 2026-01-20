#!/bin/bash

# Application scaling script
set -e

echo "⚡ Scaling Xoleric application..."

# Load environment variables
source /opt/xoleric/.env.production

# Check current load
CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2*100}')
ACTIVE_USERS=$(docker exec xoleric-redis redis-cli SCARD online_users)

echo "Current metrics:"
echo "- CPU Load: $CPU_LOAD"
echo "- Memory Usage: ${MEM_USAGE}%"
echo "- Active Users: $ACTIVE_USERS"

# Scaling thresholds
SCALE_UP_CPU=2.0
SCALE_DOWN_CPU=0.5
SCALE_UP_USERS=1000
SCALE_DOWN_USERS=100

# Get current replica count
CURRENT_REPLICAS=$(docker-compose -f /opt/xoleric/docker-compose.prod.yml ps backend | grep -c "Up")

# Auto-scaling logic
if (( $(echo "$CPU_LOAD > $SCALE_UP_CPU" | bc -l) )) || [ $ACTIVE_USERS -gt $SCALE_UP_USERS ]; then
    echo "Scaling UP due to high load..."
    NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
    
    # Limit max replicas
    if [ $NEW_REPLICAS -gt 5 ]; then
        NEW_REPLICAS=5
        echo "Maximum replicas reached (5)"
    fi
    
    # Scale backend
    docker-compose -f /opt/xoleric/docker-compose.prod.yml up -d --scale backend=$NEW_REPLICAS --no-recreate backend
    
    # Update load balancer configuration
    sed -i "s/backend:5000/backend:5000 backend2:5000 backend3:5000/g" /etc/nginx/nginx.conf
    nginx -s reload
    
    echo "Scaled backend to $NEW_REPLICAS replicas"
    
elif (( $(echo "$CPU_LOAD < $SCALE_DOWN_CPU" | bc -l) )) && [ $ACTIVE_USERS -lt $SCALE_DOWN_USERS ] && [ $CURRENT_REPLICAS -gt 1 ]; then
    echo "Scaling DOWN due to low load..."
    NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
    
    # Limit min replicas
    if [ $NEW_REPLICAS -lt 1 ]; then
        NEW_REPLICAS=1
    fi
    
    # Scale down
    docker-compose -f /opt/xoleric/docker-compose.prod.yml up -d --scale backend=$NEW_REPLICAS --no-recreate backend
    
    echo "Scaled backend down to $NEW_REPLICAS replicas"
    
else
    echo "No scaling needed at this time"
fi

# Monitor and log scaling event
cat >> /opt/xoleric/logs/scaling.log << EOF
$(date): CPU=$CPU_LOAD, MEM=${MEM_USAGE}%, USERS=$ACTIVE_USERS, REPLICAS=$CURRENT_REPLICAS->$NEW_REPLICAS
EOF

echo "✅ Scaling completed!"
