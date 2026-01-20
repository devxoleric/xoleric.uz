#!/bin/bash

# SSL certificate renewal script
set -e

echo "🔄 Checking SSL certificate renewal..."

# Check certificate expiration
CERT_FILE="/etc/nginx/ssl/xoleric.net.crt"
if [ ! -f "$CERT_FILE" ]; then
    echo "❌ Certificate file not found"
    exit 1
fi

EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -enddate -noout | cut -d= -f2)
DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))

echo "Certificate expires on: $EXPIRY_DATE"
echo "Days left: $DAYS_LEFT"

# Renew if less than 30 days left
if [ $DAYS_LEFT -lt 30 ]; then
    echo "Renewing SSL certificate..."
    
    # Stop nginx
    systemctl stop nginx || docker-compose -f /opt/xoleric/docker-compose.prod.yml stop nginx
    
    # Renew certificate
    certbot renew --non-interactive --agree-tos
    
    # Copy new certificates
    cp /etc/letsencrypt/live/xoleric.net/fullchain.pem /etc/nginx/ssl/xoleric.net.crt
    cp /etc/letsencrypt/live/xoleric.net/privkey.pem /etc/nginx/ssl/xoleric.net.key
    
    # Set permissions
    chmod 600 /etc/nginx/ssl/*
    
    # Start nginx
    systemctl start nginx || docker-compose -f /opt/xoleric/docker-compose.prod.yml start nginx
    
    # Reload nginx
    nginx -s reload
    
    # Backup new certificates
    cp /etc/nginx/ssl/* /opt/xoleric/ssl/
    
    echo "✅ Certificate renewed successfully!"
    
    # Send notification
    if [ ! -z "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"✅ SSL certificate renewed for xoleric.net. New expiry: $EXPIRY_DATE\"}" \
            "$SLACK_WEBHOOK_URL"
    fi
else
    echo "✅ Certificate is still valid for $DAYS_LEFT days"
fi
