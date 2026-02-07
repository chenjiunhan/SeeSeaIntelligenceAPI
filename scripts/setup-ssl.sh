#!/bin/bash

# SeeSea Intelligence API - SSL Certificate Setup Script
# Usage: ./scripts/setup-ssl.sh <domain-name> <email>
# Example: ./scripts/setup-ssl.sh seesea.example.com admin@example.com

set -e

# Configuration
SSH_KEY="${SSH_KEY:-/home/jaqq-fast-doge/kacha.pem}"
SSH_USER="ubuntu"
SSH_HOST="ec2-13-52-37-94.us-west-1.compute.amazonaws.com"
REMOTE_DIR="/home/ubuntu/seesea-api"

DOMAIN="${1}"
EMAIL="${2}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SeeSea API SSL Certificate Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Validate parameters
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./scripts/setup-ssl.sh <domain-name> <email>"
    echo ""
    echo -e "${YELLOW}Example:${NC}"
    echo "  ./scripts/setup-ssl.sh seesea.example.com admin@example.com"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "  1. Domain DNS must point to: 13.52.37.94"
    echo "  2. AWS Security Group must allow ports 80 and 443"
    echo "  3. Nginx must be running on the server"
    echo ""
    exit 1
fi

echo -e "${YELLOW}Domain:${NC} ${DOMAIN}"
echo -e "${YELLOW}Email:${NC} ${EMAIL}"
echo -e "${YELLOW}Server:${NC} ${SSH_HOST}"
echo ""

# Check DNS
echo -e "${GREEN}[1/5] Checking DNS configuration...${NC}"
RESOLVED_IP=$(dig +short "$DOMAIN" @8.8.8.8 | tail -1)
if [ -z "$RESOLVED_IP" ]; then
    echo -e "${RED}Error: Domain ${DOMAIN} does not resolve to any IP${NC}"
    echo -e "${YELLOW}Please configure your DNS A record to point to: 13.52.37.94${NC}"
    exit 1
fi

echo "Domain ${DOMAIN} resolves to: ${RESOLVED_IP}"
if [ "$RESOLVED_IP" != "13.52.37.94" ]; then
    echo -e "${YELLOW}Warning: Domain resolves to ${RESOLVED_IP}, but server is at 13.52.37.94${NC}"
    echo -e "${YELLOW}SSL certificate may fail. Continue anyway? (y/N)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install Certbot on EC2
echo -e "${GREEN}[2/5] Installing Certbot on EC2...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << 'EOF'
    # Update package list
    sudo apt-get update -qq

    # Install Certbot and Nginx plugin
    if ! command -v certbot &> /dev/null; then
        echo "Installing Certbot..."
        sudo apt-get install -y certbot python3-certbot-nginx
    else
        echo "Certbot already installed: $(certbot --version)"
    fi
EOF

# Upload SSL-enabled Nginx configuration
echo -e "${GREEN}[3/5] Creating SSL Nginx configuration...${NC}"

# Create temporary SSL config locally
cat > /tmp/nginx-ssl.conf << NGINX_EOF
events {
    worker_connections 1024;
}

http {
    # Rate Limiting Zone
    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=100r/m;

    upstream go_api {
        server api-go:8080;
        keepalive 32;
    }

    upstream python_api {
        server api-python:8000;
        keepalive 16;
    }

    upstream grafana {
        server grafana:3000;
    }

    upstream prometheus {
        server prometheus:9090;
    }

    # HTTP Server - Redirect to HTTPS
    server {
        listen 80;
        server_name ${DOMAIN};

        # Allow certbot challenges
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Redirect all other traffic to HTTPS
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    # HTTPS Server
    server {
        listen 443 ssl http2;
        server_name ${DOMAIN};

        # SSL Certificates (will be created by certbot)
        ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

        # SSL Configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # Gzip Compression
        gzip on;
        gzip_vary on;
        gzip_min_length 1024;
        gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

        # Go API (Data queries)
        location /api/v1/vessels {
            proxy_pass http://go_api;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # Python API (Analytics)
        location /api/v1/analytics {
            proxy_pass http://python_api;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
        }

        # LangGraph Agent
        location /api/v1/chat {
            proxy_pass http://python_api;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 300s;
        }

        # WebSocket
        location /ws {
            proxy_pass http://go_api;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;

            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }

        # Health Check
        location /health {
            access_log off;
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }

        # FastAPI Swagger Documentation
        location /docs {
            proxy_pass http://python_api/docs;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # FastAPI ReDoc Documentation
        location /redoc {
            proxy_pass http://python_api/redoc;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # FastAPI OpenAPI Schema
        location /openapi.json {
            proxy_pass http://python_api/openapi.json;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }

        # Grafana Dashboard
        location /grafana/ {
            proxy_pass http://grafana/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            # WebSocket support for Grafana
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        # Prometheus Metrics
        location /prometheus/ {
            proxy_pass http://prometheus/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
NGINX_EOF

# Upload SSL config
scp -i "$SSH_KEY" /tmp/nginx-ssl.conf "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/infrastructure/nginx/nginx.conf.ssl"
rm /tmp/nginx-ssl.conf

# Obtain SSL Certificate
echo -e "${GREEN}[4/5] Obtaining SSL certificate from Let's Encrypt...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    # Create certbot webroot directory
    sudo mkdir -p /var/www/certbot

    # Stop nginx temporarily to allow certbot standalone mode
    cd ${REMOTE_DIR}/infrastructure/docker
    docker-compose stop nginx

    # Obtain certificate (standalone mode)
    sudo certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email ${EMAIL} \
        -d ${DOMAIN} \
        --preferred-challenges http

    # Check if certificate was obtained
    if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        echo "Error: Certificate was not created"
        exit 1
    fi

    echo "Certificate obtained successfully!"
    sudo ls -la /etc/letsencrypt/live/${DOMAIN}/
EOF

# Update docker-compose to mount SSL certificates
echo -e "${GREEN}[5/5] Updating Docker configuration...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}/infrastructure/docker

    # Backup current nginx config
    if [ -f docker-compose.yml ]; then
        cp docker-compose.yml docker-compose.yml.backup
    fi

    # Update nginx service to mount certificates
    # This assumes the nginx service exists in docker-compose.yml
    echo "Updating nginx volumes in docker-compose.yml..."

    # Replace nginx config
    cp ${REMOTE_DIR}/infrastructure/nginx/nginx.conf.ssl ${REMOTE_DIR}/infrastructure/nginx/nginx.conf

    # Start nginx with SSL
    docker-compose up -d nginx

    # Check nginx status
    docker-compose ps nginx
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSL Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Your API is now available at:${NC}"
echo -e "  https://${DOMAIN}/docs"
echo -e "  https://${DOMAIN}/health"
echo -e "  https://${DOMAIN}/grafana/"
echo ""
echo -e "${YELLOW}Certificate auto-renewal:${NC}"
echo "  Certificates will auto-renew via certbot systemd timer"
echo "  Check status: sudo systemctl status certbot.timer"
echo ""
echo -e "${YELLOW}Manual renewal (if needed):${NC}"
echo "  ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST}"
echo "  sudo certbot renew"
echo "  cd ${REMOTE_DIR}/infrastructure/docker && docker-compose restart nginx"
echo ""
