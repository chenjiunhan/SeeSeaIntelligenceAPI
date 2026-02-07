#!/bin/bash

# SeeSea Intelligence API - AWS EC2 Rollback Script
# Usage: ./scripts/rollback-aws.sh [backup-name]
# Example: ./scripts/rollback-aws.sh backup-20260207-143022

set -e

# Configuration
SSH_KEY="${SSH_KEY:-/home/jaqq-fast-doge/kacha.pem}"
SSH_USER="ubuntu"
SSH_HOST="ec2-13-52-37-94.us-west-1.compute.amazonaws.com"
REMOTE_DIR="/home/ubuntu/seesea-api"
BACKUP_NAME="${1}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SeeSea API Rollback${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check SSH key
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found at ${SSH_KEY}${NC}"
    exit 1
fi

# List available backups if no backup name provided
if [ -z "$BACKUP_NAME" ]; then
    echo -e "${YELLOW}Available backups:${NC}"
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
        cd ${REMOTE_DIR}/backup 2>/dev/null || { echo "No backups found"; exit 1; }
        ls -lt | grep '^d' | awk '{print \$9}' | head -10
EOF
    echo ""
    echo -e "${YELLOW}Usage: ./scripts/rollback-aws.sh <backup-name>${NC}"
    exit 0
fi

echo -e "${YELLOW}Rolling back to: ${BACKUP_NAME}${NC}"
echo ""

# Verify backup exists
echo -e "${GREEN}[1/4] Verifying backup exists...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    if [ ! -d "${REMOTE_DIR}/backup/${BACKUP_NAME}" ]; then
        echo "Error: Backup ${BACKUP_NAME} not found"
        exit 1
    fi
    echo "Backup found: ${BACKUP_NAME}"
EOF

# Stop current services
echo -e "${GREEN}[2/4] Stopping current services...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}/infrastructure/docker
    docker-compose down
EOF

# Restore backup
echo -e "${GREEN}[3/4] Restoring backup...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}

    # Backup current state before rollback
    ROLLBACK_BACKUP="backup/rollback-before-\$(date +%Y%m%d-%H%M%S)"
    mkdir -p "\${ROLLBACK_BACKUP}"
    cp -r api-go "\${ROLLBACK_BACKUP}/" 2>/dev/null || true
    cp -r api-python "\${ROLLBACK_BACKUP}/" 2>/dev/null || true
    cp -r etl "\${ROLLBACK_BACKUP}/" 2>/dev/null || true
    cp -r ../SeeSeaIntelligence "\${ROLLBACK_BACKUP}/" 2>/dev/null || true
    cp infrastructure/docker/.env "\${ROLLBACK_BACKUP}/" 2>/dev/null || true

    # Restore from backup
    rm -rf api-go api-python etl
    rm -rf ../SeeSeaIntelligence
    cp -r backup/${BACKUP_NAME}/api-go . 2>/dev/null || true
    cp -r backup/${BACKUP_NAME}/api-python . 2>/dev/null || true
    cp -r backup/${BACKUP_NAME}/etl . 2>/dev/null || true
    cp -r backup/${BACKUP_NAME}/SeeSeaIntelligence ../SeeSeaIntelligence 2>/dev/null || true
    cp backup/${BACKUP_NAME}/.env infrastructure/docker/.env 2>/dev/null || true

    echo "Restored from backup: ${BACKUP_NAME}"
EOF

# Restart services
echo -e "${GREEN}[4/4] Restarting services...${NC}"
ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" << EOF
    cd ${REMOTE_DIR}/infrastructure/docker
    docker-compose up -d
    sleep 10
    docker-compose ps
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Rollback Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Rolled back to: ${BACKUP_NAME}${NC}"
echo ""
