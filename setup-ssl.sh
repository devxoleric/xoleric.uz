#!/bin/bash

# SSL certificate setup script for .NET domain
set -e

echo "🔐 Setting up SSL certificates for xoleric.net..."

# Create SSL directory
mkdir -p /etc/nginx/ssl
mkdir -p /opt/xoleric/ssl

# Check if Certbot is available
if command -v certbot &> /dev/null; then
    echo "Using Certbot for SSL certificates..."
    
    # Stop nginx temporarily
    systemctl stop nginx || docker-compose stop nginx
    
    # Request certificates
    certbot certonly --standalone \
        -d xoleric.net \
        -d www.xoleric.net \
        -d api.xoleric.net \
        -d ws.xoleric.net \
        -d monitor.xoleric.net \
        -d grafana.xoleric.net \
        -d logs.xoleric.net \
        --non-interactive \
        --agree-tos \
        --email admin@xoleric.net \
        --expand
    
    # Copy certificates to nginx directory
    cp /etc/letsencrypt/live/xoleric.net/fullchain.pem /etc/nginx/ssl/xoleric.net.crt
    cp /etc/letsencrypt/live/xoleric.net/privkey.pem /etc/nginx/ssl/xoleric.net.key
    
    # Set proper permissions
    chmod 600 /etc/nginx/ssl/*
    chown nginx:nginx /etc/nginx/ssl/*
    
    # Start nginx
    systemctl start nginx || docker-compose start nginx
    
    # Create renewal hook
    cat > /etc/letsencrypt/renewal-hooks/deploy/nginx.sh << 'EOF'
#!/bin/bash
cp /etc/letsencrypt/live/xoleric.net/fullchain.pem /etc/nginx/ssl/xoleric.net.crt
cp /etc/letsencrypt/live/xoleric.net/privkey.pem /etc/nginx/ssl/xoleric.net.key
systemctl reload nginx
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx.sh
    
else
    echo "Certbot not available, generating self-signed certificates..."
    
    # Generate self-signed certificates
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/xoleric.net.key \
        -out /etc/nginx/ssl/xoleric.net.crt \
        -subj "/C=UZ/ST=Tashkent/L=Tashkent/O=Xoleric/CN=xoleric.net"
    
    # Copy for other subdomains
    cp /etc/nginx/ssl/xoleric.net.key /etc/nginx/ssl/api.xoleric.net.key
    cp /etc/nginx/ssl/xoleric.net.crt /etc/nginx/ssl/api.xoleric.net.crt
    cp /etc/nginx/ssl/xoleric.net.key /etc/nginx/ssl/ws.xoleric.net.key
    cp /etc/nginx/ssl/xoleric.net.crt /etc/nginx/ssl/ws.xoleric.net.crt
    
    # Set permissions
    chmod 600 /etc/nginx/ssl/*
fi

# Create DH parameters for stronger security
if [ ! -f /etc/nginx/ssl/dhparam.pem ]; then
    echo "Generating DH parameters (this may take a while)..."
    openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
fi

# Backup certificates
cp /etc/nginx/ssl/* /opt/xoleric/ssl/

echo "✅ SSL certificates setup completed!"
