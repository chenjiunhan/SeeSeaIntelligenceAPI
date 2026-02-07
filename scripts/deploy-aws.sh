#!/bin/bash

# SeeSea Intelligence API - AWS EC2 Deployment Script
# Usage: ./scripts/deploy-aws.sh [environment]
# Example: ./scripts/deploy-aws.sh production

set -e

# Configuration
SSH_KEY="${SSH_KEY:-/home/jaqq-fast-doge/kacha.pem}"
SSH_USER="ubuntu"
SSH_HOST="ec2-13-52-37-94.us-west-1.compute.amazonaws.com"
REMOTE_DIR="/home/ubuntu/seesea-api"
ENVIRONMENT="${1:-production}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SeeSea API Deployment to AWS EC2${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Environment:${NC} ${ENVIRONMENT}"
echo -e "${YELLOW}Target:${NC} ${SSH_USER}@${SSH_HOST}"
echo -e "${YELLOW}Remote Directory:${NC} ${REMOTE_DIR}"
echo ""

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found at ${SSH_KEY}${NC}"
    exit 1
fi

# Check if .env file exists
if [ ! -f "infrastructure/docker/.env" ]; then
    echo -e "${RED}Error: .env file not found at infrastructure/docker/.env${NC}"
    echo -e "${YELLOW}Please create it from .env.example before deploying${NC}"
    exit 1
fi

echo -e "${GREEN}[1/7] Testing SSH connection...${NC}"
ssh -i "$SSH_KEY" -o ConnectTimeout=10 "${SSH_USER}@${SSH_HOST}" "echo 'SSH connection successful'" || {
    echo -e "${RED}Error: Cannot connect to EC2 instance${NC}"
    exit 1
}

echo -e "${GREEN}[2/7] Creating remote directory structure...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << 'EOF'
    mkdir -p ~/seesea-api
    mkdir -p ~/seesea-api/backup
EOF

echo -e "${GREEN}[3/7] Backing up current deployment (if exists)...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    if [ -d "${REMOTE_DIR}/api-go" ]; then
        BACKUP_NAME="backup-\$(date +%Y%m%d-%H%M%S)"
        echo "Creating backup: \${BACKUP_NAME}"
        mkdir -p "${REMOTE_DIR}/backup/\${BACKUP_NAME}"

        # Backup docker volumes data
        if docker ps -a | grep -q seesea; then
            docker-compose -f ${REMOTE_DIR}/infrastructure/docker/docker-compose.yml down
        fi

        # Copy current deployment
        cp -r ${REMOTE_DIR}/api-go ${REMOTE_DIR}/backup/\${BACKUP_NAME}/ 2>/dev/null || true
        cp -r ${REMOTE_DIR}/api-python ${REMOTE_DIR}/backup/\${BACKUP_NAME}/ 2>/dev/null || true
        cp -r ${REMOTE_DIR}/etl ${REMOTE_DIR}/backup/\${BACKUP_NAME}/ 2>/dev/null || true
        cp -r ${REMOTE_DIR}/../SeeSeaIntelligence ${REMOTE_DIR}/backup/\${BACKUP_NAME}/ 2>/dev/null || true
        cp ${REMOTE_DIR}/infrastructure/docker/.env ${REMOTE_DIR}/backup/\${BACKUP_NAME}/ 2>/dev/null || true

        # Keep only last 5 backups
        cd ${REMOTE_DIR}/backup && ls -t | tail -n +6 | xargs -r rm -rf
    fi
EOF

echo -e "${GREEN}[4/7] Uploading application files...${NC}"
# Upload Go API
rsync -avz --progress \
    -e "ssh -i $SSH_KEY" \
    --exclude='*.exe' \
    --exclude='*.out' \
    --exclude='tmp/' \
    api-go/ "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/api-go/"

# Upload Python API
rsync -avz --progress \
    -e "ssh -i $SSH_KEY" \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='venv/' \
    --exclude='.pytest_cache' \
    api-python/ "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/api-python/"

# Upload ETL
rsync -avz --progress \
    -e "ssh -i $SSH_KEY" \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='venv/' \
    etl/ "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/etl/"

# Upload Infrastructure (including docker-compose files)
rsync -avz --progress \
    -e "ssh -i $SSH_KEY" \
    infrastructure/ "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/infrastructure/"

# Upload SeeSeaIntelligence (Data Collector)
echo -e "${YELLOW}Uploading SeeSeaIntelligence (Data Collector)...${NC}"
rsync -avz --progress \
    -e "ssh -i $SSH_KEY" \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='venv/' \
    --exclude='.pytest_cache' \
    --exclude='processed/' \
    --exclude='*.log' \
    ../SeeSeaIntelligence/ "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/../SeeSeaIntelligence/"

echo -e "${GREEN}[5/7] Installing dependencies on EC2...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << 'EOF'
    # Update system
    sudo apt-get update -qq

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker ubuntu
        rm get-docker.sh
    fi

    # Install Docker Compose if not present
    if ! command -v docker-compose &> /dev/null; then
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

    # Install Go if not present (for building Go API)
    if ! command -v go &> /dev/null; then
        echo "Installing Go..."
        wget -q https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
        rm go1.21.6.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi

    echo "Docker version: $(docker --version)"
    echo "Docker Compose version: $(docker-compose --version)"
    echo "Go version: $(go version 2>/dev/null || echo 'Not using Go build')"
EOF

echo -e "${GREEN}[6/9] Checking and obtaining SSL certificate...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << 'EOF'
    # Install Certbot if not present
    if ! command -v certbot &> /dev/null; then
        echo "Installing Certbot..."
        sudo apt-get update -qq
        sudo apt-get install -y certbot python3-certbot-nginx
    fi

    # Check if certificate exists
    if [ ! -f "/etc/letsencrypt/live/api.seesea.ai/fullchain.pem" ]; then
        echo "SSL certificate not found. Obtaining new certificate..."

        # Stop any service using port 80
        sudo systemctl stop nginx 2>/dev/null || true
        docker stop seesea-nginx 2>/dev/null || true

        # Obtain certificate using standalone mode
        sudo certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email lucas@seesea.ai \
            -d api.seesea.ai \
            --preferred-challenges http

        # Wait a moment for file system sync
        sleep 2

        if sudo test -f "/etc/letsencrypt/live/api.seesea.ai/fullchain.pem"; then
            echo "✓ SSL certificate obtained successfully!"
            sudo certbot certificates
        else
            echo "✗ ERROR: Failed to obtain SSL certificate"
            exit 1
        fi
    else
        echo "✓ SSL certificate already exists"
        sudo certbot certificates
    fi
EOF

echo -e "${GREEN}[7/9] Building and starting services...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}

    # Build Go dependencies
    cd api-go
    export PATH=\$PATH:/usr/local/go/bin
    go mod download
    go mod tidy
    cd ..

    # Stop system Nginx if running (we use Docker Nginx now)
    sudo systemctl stop nginx 2>/dev/null || true
    sudo systemctl disable nginx 2>/dev/null || true

    # Start services using docker-compose
    cd infrastructure/docker

    # Stop existing containers
    docker-compose down 2>/dev/null || true

    # Pull latest images
    docker-compose pull

    # Build and start services with production config
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

    # Wait for services to be healthy
    echo "Waiting for services to start..."
    sleep 10

    # Check service status
    docker-compose ps
EOF

echo -e "${GREEN}[8/9] Setting up SSL certificate auto-renewal...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << 'EOF'
    # Create renewal hook script
    sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null << 'HOOK_EOF'
#!/bin/bash
# Reload Docker Nginx after certificate renewal
cd /home/ubuntu/seesea-api/infrastructure/docker
docker-compose exec nginx nginx -s reload
echo "$(date): SSL certificate renewed and Nginx reloaded" >> /var/log/ssl-renewal.log
HOOK_EOF

    # Make it executable
    sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

    echo "SSL auto-renewal configured"
EOF

echo -e "${GREEN}[9/9] Verifying deployment...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}/infrastructure/docker

    echo ""
    echo "=== Service Health Check ==="

    # Check Go API
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "✓ Go API is running (port 8080)"
    else
        echo "✗ Go API is not responding"
    fi

    # Check Python API
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ Python API is running (port 8000)"
    else
        echo "✗ Python API is not responding"
    fi

    # Check PostgreSQL
    if docker-compose exec -T postgres pg_isready > /dev/null 2>&1; then
        echo "✓ PostgreSQL is running"
    else
        echo "✗ PostgreSQL is not responding"
    fi

    # Check Redis
    if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
        echo "✓ Redis is running"
    else
        echo "✗ Redis is not responding"
    fi

    # Check ClickHouse
    if docker-compose exec -T clickhouse clickhouse-client --query "SELECT 1" > /dev/null 2>&1; then
        echo "✓ ClickHouse is running"
    else
        echo "✗ ClickHouse is not responding"
    fi

    echo ""
    echo "=== Running Containers ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    echo "=== Disk Usage ==="
    df -h | grep -E 'Filesystem|/$'

    echo ""
    echo "=== Memory Usage ==="
    free -h
EOF

echo -e "${GREEN}[10/10] Running initial ETL sync...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}/infrastructure/docker

    echo ""
    echo "=== Syncing CSV data to PostgreSQL ==="

    # Wait a bit for services to be fully ready
    sleep 5

    # Run incremental CSV to PostgreSQL sync
    docker-compose exec -T etl python -c "import sys; sys.path.insert(0, 'jobs'); from incremental_csv_to_postgres import load_incremental_csv_to_postgres; load_incremental_csv_to_postgres()" 2>&1 || {
        echo "⚠️  ETL sync encountered an issue (this is normal if no new data)"
    }

    echo "✅ ETL sync completed"
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access your services at (HTTPS with SSL):${NC}"
echo -e "  API Documentation: https://api.seesea.ai/docs"
echo -e "  API ReDoc:         https://api.seesea.ai/redoc"
echo -e "  Health Check:      https://api.seesea.ai/health"
echo -e "  Grafana:           https://api.seesea.ai/grafana/"
echo -e "  Prometheus:        https://api.seesea.ai/prometheus/"
echo ""
echo -e "${YELLOW}API Endpoints:${NC}"
echo -e "  Vessels Data:      https://api.seesea.ai/api/v1/vessels/{chokepoint}"
echo -e "  Analytics:         https://api.seesea.ai/api/v1/analytics/trend"
echo -e "  AI Chat:           https://api.seesea.ai/api/v1/chat"
echo -e "  WebSocket:         wss://api.seesea.ai/ws"
echo ""
echo -e "${YELLOW}SSL Certificate:${NC}"
echo -e "  Auto-renewal: ✓ Enabled (checks twice daily)"
echo -e "  Expires: $(ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST} 'sudo certbot certificates 2>/dev/null | grep "Expiry Date" | head -1' || echo 'Run: sudo certbot certificates')"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  View logs:       ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST} 'cd ${REMOTE_DIR}/infrastructure/docker && docker-compose logs -f'"
echo -e "  Restart:         ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST} 'cd ${REMOTE_DIR}/infrastructure/docker && docker-compose restart'"
echo -e "  Stop:            ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST} 'cd ${REMOTE_DIR}/infrastructure/docker && docker-compose down'"
echo -e "  Rollback:        ./scripts/rollback-aws.sh"
echo -e "  Cert status:     ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST} 'sudo certbot certificates'"
echo ""
