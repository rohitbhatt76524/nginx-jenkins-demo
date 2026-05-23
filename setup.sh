#!/bin/bash
# ============================================================
#  setup.sh - Bootstrap Jenkins + Docker + Nginx Pipeline
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║   Jenkins + GitHub + Nginx Docker Setup  ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Create Docker network
echo -e "${YELLOW}[1/4] Creating Docker network...${NC}"
docker network create jenkins-net 2>/dev/null || echo "  Network already exists, skipping."

# Step 2: Create Jenkins volume
echo -e "${YELLOW}[2/4] Creating Jenkins volume...${NC}"
docker volume create jenkins-data 2>/dev/null || echo "  Volume already exists, skipping."

# Step 3: Run Jenkins
echo -e "${YELLOW}[3/4] Starting Jenkins container...${NC}"
docker stop jenkins 2>/dev/null || true
docker rm   jenkins 2>/dev/null || true

docker run -d \
  --name jenkins \
  --network jenkins-net \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins-data:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(which docker)":/usr/bin/docker \
  --restart=unless-stopped \
  jenkins/jenkins:lts

echo "  Waiting for Jenkins to start..."
sleep 10

# Step 4: Fix Docker socket permissions
echo -e "${YELLOW}[4/4] Fixing Docker socket permissions...${NC}"
docker exec -u root jenkins chmod 666 /var/run/docker.sock

# Done
echo ""
echo -e "${GREEN}✅ Jenkins is running!${NC}"
echo ""
echo -e "  🌐 Jenkins UI:     ${YELLOW}http://localhost:8080${NC}"
echo ""
echo -e "  🔑 Initial Admin Password:"
echo -e "${YELLOW}"
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "  (still starting... run: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)"
echo -e "${NC}"
echo ""
echo "Next steps:"
echo "  1. Open http://localhost:8080 and paste the password above"
echo "  2. Install suggested plugins"
echo "  3. Add GitHub credentials (Manage Jenkins → Credentials)"
echo "  4. Create a Pipeline job pointing to your GitHub repo"
echo "  5. Push to GitHub to trigger automatic deployments!"
echo ""
