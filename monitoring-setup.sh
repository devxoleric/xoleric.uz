#!/bin/bash

# Monitoring setup script
set -e

echo "📊 Setting up monitoring..."

# Create monitoring directories
mkdir -p /opt/xoleric/monitoring
mkdir -p /opt/xoleric/monitoring/dashboards
mkdir -p /opt/xoleric/monitoring/alerts

# Create Prometheus configuration
cat > /opt/xoleric/monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - "alerts/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'xoleric-backend'
    static_configs:
      - targets: ['backend:5000']
    metrics_path: '/metrics'

  - job_name: 'xoleric-postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'xoleric-redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'xoleric-nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

# Create Grafana dashboard provisioning
mkdir -p /opt/xoleric/monitoring/dashboards

cat > /opt/xoleric/monitoring/dashboards/xoleric-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "Xoleric Platform Dashboard",
    "panels": [
      {
        "title": "System Metrics",
        "type": "graph"
      }
    ]
  }
}
EOF

# Create alert rules
cat > /opt/xoleric/monitoring/alerts/rules.yml << 'EOF'
groups:
  - name: xoleric_alerts
    rules:
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 80%"
      
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80%"
      
      - alert: DatabaseDown
        expr: up{job="xoleric-postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Database is down"
          description: "PostgreSQL database is not responding"
      
      - alert: BackendDown
        expr: up{job="xoleric-backend"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Backend API is down"
          description: "Xoleric backend API is not responding"
      
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100 > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate on {{ $labels.instance }}"
          description: "Error rate is above 5%"
EOF

# Setup log rotation
cat > /etc/logrotate.d/xoleric << 'EOF'
/opt/xoleric/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        docker exec xoleric-backend pkill -HUP node
    endscript
}
EOF

# Install monitoring exporters if not using Docker
if [ "$USE_DOCKER" != "true" ]; then
    echo "Installing monitoring exporters..."
    
    # Node exporter
    wget https://github.com/prometheus/node_exporter/releases/download/v1.6.0/node_exporter-1.6.0.linux-amd64.tar.gz
    tar xvf node_exporter-1.6.0.linux-amd64.tar.gz
    cp node_exporter-1.6.0.linux-amd64/node_exporter /usr/local/bin/
    
    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
fi

echo "✅ Monitoring setup completed!"
