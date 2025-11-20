#!/bin/bash

set -euo pipefail

# Remove duplicate startup commands and redundant configurations, optimize compatibility, add certificate verification and troubleshooting capabilities
echo "====== 🚀 n8n + Traefik Stable Deployment Script (Certificate Verification Enhanced Version) ======"

# Check dependent tools (jq for parsing acme.json, openssl for certificate verification)
check_dependencies() {
    local missing=()
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "🔧 Installing missing dependencies: ${missing[*]}"
        apt-get update &> /dev/null
        apt-get install -y "${missing[@]}" &> /dev/null
    fi
}

# Get user input (add format validation hints)
read -p "🌐 Enter your domain name (e.g., n8n.example.com, no https://): " DOMAIN
read -p "📧 Enter your email (for Let's Encrypt certificate application): " EMAIL
read -p "👤 Enter n8n login username: " N8N_USER
read -p "🔒 Enter n8n login password (8+ characters recommended): " N8N_PASS

# Install dependent tools
check_dependencies

# Install Docker (if not installed, use official script)
if ! command -v docker &> /dev/null; then
    echo "🔧 Installing Docker (please wait)..."
    curl -fsSL https://get.docker.com | bash
    # Start Docker service and set to auto-start on boot
    systemctl enable --now docker
fi

# Install Docker Compose Plugin (compatible with Docker 20+ versions)
if ! docker compose version &> /dev/null; then
    echo "🔧 Installing Docker Compose Plugin..."
    apt-get update &> /dev/null
    apt-get install -y docker-compose-plugin &> /dev/null
fi

# Create working directory and enter (avoid directory conflicts)
mkdir -p ~/n8n-docker && cd ~/n8n-docker

# Clean up old configurations (avoid residual file interference, keep backup option)
if [ -f docker-compose.yml ] || [ -d traefik ]; then
    echo "📦 Backing up old configuration files..."
    mv -f docker-compose.yml docker-compose.old.$(date +%Y%m%d%H%M%S) 2>/dev/null
    mv -f traefik traefik.old.$(date +%Y%m%d%H%M%S) 2>/dev/null
fi

# Create Traefik-related directories and certificate files (permissions are critical)
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json  # Certificate file must have 600 permissions, otherwise application fails
chown root:root traefik/acme.json  # Ensure root permissions to avoid permission anomalies

# Create n8n data directory (adapt to container user permissions)
mkdir -p n8n_data
chown -R 1000:1000 n8n_data  # n8n container uses node user (UID=1000)
chmod -R 700 n8n_data

# Write Docker Compose configuration (add DEBUG logs, optimize certificate configuration)
cat <<EOF > docker-compose.yml
version: '3.8'  # Specify version for better compatibility

services:
  traefik:
    image: traefik:v2.11  # Stable version, compatible with certificate application process
    restart: always
    ports:
      - "80:80"   # HTTP port (for certificate HTTP-01 challenge)
      - "443:443" # HTTPS port (for actual access)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # Read-only permission for better security
      - ./traefik/acme.json:/letsencrypt/acme.json    # Certificate storage path
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # Certificate resolver configuration
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      # Enable DEBUG logs for easier certificate troubleshooting (change to INFO in production)
      - "--log.level=DEBUG"
      - "--accesslog=true"  # Enable access logs
    networks:
      - n8n-network

  n8n:
    image: n8nio/n8n:latest  # Use latest stable version of n8n
    restart: always
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
      - VUE_APP_URL_BASE_API=https://$DOMAIN/
      - NODE_ENV=production
      - TZ=Asia/Shanghai  # Timezone configuration to avoid time inconsistencies
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      # Force HTTP to HTTPS redirect for enhanced security
      - "traefik.http.middlewares.n8n-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.n8n-http.entrypoints=web"
      - "traefik.http.routers.n8n-http.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.n8n-http.middlewares=n8n-redirect"
    volumes:
      - ./n8n_data:/home/node/.n8n
    networks:
      - n8n-network

networks:
  n8n-network:  # Independent network for better isolation
    name: n8n-network
EOF

# Start services
echo "🚀 Starting n8n and Traefik services..."
docker compose up -d

# Certificate verification function (parse acme.json and verify certificate validity)
verify_certificate() {
    local acme_path="./traefik/acme.json"
    local max_wait=120  # Maximum wait time: 2 minutes
    local wait_count=0
    local cert_data

    echo -e "\n🔍 Verifying certificate application status (may take 30 seconds)..."

    # Wait for certificate generation
    while [ $wait_count -lt $max_wait ]; do
        if [ -s "$acme_path" ] && jq '.Certificates | length > 0' "$acme_path" &> /dev/null; then
            cert_data=$(jq -r '.Certificates[0].Certificate' "$acme_path")
            if [ "$cert_data" != "null" ] && [ -n "$cert_data" ]; then
                break
            fi
        fi
        sleep 2
        wait_count=$((wait_count + 2))
        echo -n "."
    done

    if [ $wait_count -ge $max_wait ]; then
        echo -e "\n⚠️ Certificate application timed out! Run the following command to check logs for troubleshooting:"
        echo "docker logs -f traefik | grep -i acme"
        return 1
    fi

    # Decode and verify certificate
    echo -e "\n✅ Certificate generated successfully, verifying details..."
    echo "$cert_data" | base64 -d | openssl x509 -text -noout > ./traefik/cert_details.txt

    # Extract key information
    local issuer=$(grep "Issuer:" ./traefik/cert_details.txt | head -n1 | awk -F: '{print $2-}' | xargs)
    local not_after=$(grep "Not After :" ./traefik/cert_details.txt | awk -F: '{print $2-}' | xargs)
    local subject=$(grep "Subject:" ./traefik/cert_details.txt | head -n1 | awk -F: '{print $2-}' | xargs)

    echo -e "\n📜 Certificate Verification Results:"
    echo "Issuing Authority: $issuer"
    echo "Valid Until: $not_after"
    echo "Bound Domain: $subject"

    # Clean up temporary files
    rm -f ./traefik/cert_details.txt
}

# Execute certificate verification
verify_certificate

# Deployment completion prompt (add certificate troubleshooting solutions)
echo -e "\n🎉 Deployment Successful!"
echo "👉 Access URL: https://$DOMAIN"
echo "🔐 Login Username: $N8N_USER"
echo "🔑 Login Password: $N8N_PASS"
echo "📁 Project Directory: ~/n8n-docker"
echo -e "\n⚠️ Key Operations & Troubleshooting:"
echo "1. Manual Certificate Verification Command:"
echo "   docker exec -it traefik sh -c 'cat /letsencrypt/acme.json | jq -r .Certificates[0].Certificate | base64 -d | openssl x509 -text -noout'"
echo "2. View Traefik Detailed Logs (for certificate issues):"
echo "   docker logs -f traefik | grep -i 'acme\|cert\|tls'"
echo "3. Certificate Expiry Warning: Certificates are valid for 90 days and will auto-renew before expiration"
echo "4. If certificate is valid but access fails: Clear browser cache or check if domain DNS resolution has taken effect"
echo "5. Reset Certificate: Delete traefik/acme.json and restart services to reapply"