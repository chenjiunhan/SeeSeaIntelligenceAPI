#!/bin/bash

# Setup automatic SSL certificate renewal with Docker Nginx reload
# This script should be run on the EC2 instance once

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up automatic SSL certificate renewal...${NC}"

# Create renewal hook script
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null << 'EOF'
#!/bin/bash
# Reload Docker Nginx after certificate renewal
cd /home/ubuntu/seesea-api/infrastructure/docker
docker-compose exec nginx nginx -s reload
echo "$(date): SSL certificate renewed and Nginx reloaded" >> /var/log/ssl-renewal.log
EOF

# Make it executable
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# Test renewal (dry run)
echo -e "${YELLOW}Testing certificate renewal (dry run)...${NC}"
sudo certbot renew --dry-run

echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo -e "${YELLOW}Certificate renewal is now automated:${NC}"
echo "- Certbot checks twice daily (systemd timer)"
echo "- Certificates renew automatically when < 30 days remaining"
echo "- Docker Nginx reloads automatically after renewal"
echo ""
echo -e "${YELLOW}Manual renewal (if needed):${NC}"
echo "  sudo certbot renew"
echo ""
echo -e "${YELLOW}Check renewal status:${NC}"
echo "  sudo systemctl status certbot.timer"
echo "  sudo certbot certificates"
echo ""
