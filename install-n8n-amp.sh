#!/bin/bash
# AMP n8n Module Auto-Installer
# Run as root: chmod +x install-n8n-amp.sh && ./install-n8n-amp.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
[[ $EUID -eq 0 ]] || error "Must run as root"

# Detect AMP installation
AMP_USER="amp"
AMP_DATA_DIR="/home/amp/.ampdata"
if [[ ! -d "$AMP_DATA_DIR" ]]; then
    AMP_DATA_DIR="/opt/cubecoders/amp/.ampdata"
    [[ -d "$AMP_DATA_DIR" ]] || error "AMP installation not found"
fi

TEMPLATE_DIR="$AMP_DATA_DIR/Plugins/ADSModule/GenericTemplates"
APP_DIR="/opt/n8n"

log "Installing n8n AMP module..."
log "AMP Data Dir: $AMP_DATA_DIR"

# Install Docker if missing
if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    apt-get update
    apt-get install -y docker.io docker-compose
    systemctl enable docker
    systemctl start docker
    usermod -aG docker $AMP_USER
fi

# Create directories
log "Creating directories..."
mkdir -p "$TEMPLATE_DIR"
mkdir -p "$APP_DIR"/{ssl,backups}

# Create n8n.kvp template file
log "Creating AMP template files..."
cat > "$TEMPLATE_DIR/n8n.kvp" << 'EOF'
{
  "DisplayName": "n8n Workflow Automation",
  "Author": "Community",
  "Description": "Deploy n8n workflow automation platform with PostgreSQL backend",
  "Version": "1.0.0",
  "ModuleType": "Generic",
  "OS": "Linux",
  "Arch": "x86_64",
  "UpdateAvailable": false,
  "UpdateString": "",
  "SupportedOS": ["Linux"],
  "RequiredAMPVersion": "2.4.0.0",
  "RequiresFullLoad": false,
  "ConfigRoot": "/opt/n8n",
  "WorkingDirectory": "/opt/n8n", 
  "LinuxExecutable": "start.sh",
  "WindowsExecutable": "",
  "MacExecutable": "",
  "Stopped": true,
  "ExtraContainerPackages": ["docker.io", "docker-compose"],
  "ContainerPolicy": {
    "ContainerMaxCPU": 80,
    "ContainerMaxMemory": 2048,
    "ContainerMaxMemoryPolicy": "Reserve",
    "SupportsCPULimiting": true,
    "SupportsLiveSettingsChanges": false
  },
  "ConsoleOutputRegex": "^(?<timestamp>\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z)\\s+(?<level>\\w+)\\s+(?<message>.+)$",
  "AppReadyRegex": "^.*n8n ready on.*$",
  "AppStartedRegex": "^.*Starting n8n.*$",
  "AppStoppedRegex": "^.*Process exited.*$"
}
EOF

# Create n8nconfig.json settings file
cat > "$TEMPLATE_DIR/n8nconfig.json" << 'EOF'
{
  "DisplayName": "n8n Configuration",
  "Category": "n8n Settings",
  "Description": "Configure n8n workflow automation settings",
  "Settings": [
    {
      "DisplayName": "Hostname",
      "Category": "General", 
      "Description": "Public hostname for n8n access (domain or IP)",
      "Keywords": "hostname,domain,url",
      "Name": "N8N_HOST",
      "DefaultValue": "localhost",
      "EnumValues": {},
      "IncludeInCommandLine": false,
      "ParamFieldName": "N8N_HOST",
      "ProvisionSetting": false,
      "ReadOnly": false,
      "Required": true,
      "SkipIfEmpty": false,
      "Tag": "General",
      "Type": "text"
    },
    {
      "DisplayName": "Port",
      "Category": "General",
      "Description": "Port for n8n web interface", 
      "Keywords": "port,network",
      "Name": "N8N_PORT",
      "DefaultValue": "5678",
      "EnumValues": {},
      "IncludeInCommandLine": false,
      "ParamFieldName": "N8N_PORT",
      "ProvisionSetting": false,
      "ReadOnly": false,
      "Required": true,
      "SkipIfEmpty": false,
      "Tag": "General", 
      "Type": "number"
    },
    {
      "DisplayName": "Admin Username",
      "Category": "Security",
      "Description": "Username for n8n login",
      "Keywords": "username,login,auth",
      "Name": "N8N_USER", 
      "DefaultValue": "admin",
      "EnumValues": {},
      "IncludeInCommandLine": false,
      "ParamFieldName": "N8N_USER",
      "ProvisionSetting": false,
      "ReadOnly": false,
      "Required": true,
      "SkipIfEmpty": false,
      "Tag": "Security",
      "Type": "text"
    },
    {
      "DisplayName": "Timezone",
      "Category": "General",
      "Description": "Server timezone for scheduling", 
      "Keywords": "timezone,time,schedule",
      "Name": "TZ",
      "DefaultValue": "UTC",
      "EnumValues": {
        "UTC": "UTC",
        "America/New_York": "Eastern Time",
        "America/Chicago": "Central Time",
        "America/Denver": "Mountain Time", 
        "America/Los_Angeles": "Pacific Time",
        "Europe/London": "GMT",
        "Europe/Paris": "Central European Time"
      },
      "IncludeInCommandLine": false,
      "ParamFieldName": "TZ",
      "ProvisionSetting": false,
      "ReadOnly": false,
      "Required": false,
      "SkipIfEmpty": true,
      "Tag": "General",
      "Type": "enum"
    },
    {
      "DisplayName": "Log Level",
      "Category": "Advanced",
      "Description": "Logging verbosity level",
      "Keywords": "logging,debug,verbose",
      "Name": "N8N_LOG_LEVEL",
      "DefaultValue": "warn", 
      "EnumValues": {
        "error": "Error only",
        "warn": "Warnings and errors",
        "info": "Informational", 
        "debug": "Debug (verbose)"
      },
      "IncludeInCommandLine": false,
      "ParamFieldName": "N8N_LOG_LEVEL",
      "ProvisionSetting": false,
      "ReadOnly": false,
      "Required": false,
      "SkipIfEmpty": true,
      "Tag": "Advanced",
      "Type": "enum"
    }
  ]
}
EOF

# Create docker-compose.yml
log "Creating application files..."
cat > "$APP_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 30s
      timeout: 10s
      retries: 3

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${N8N_HOST}/
      - GENERIC_TIMEZONE=${TZ:-UTC}
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL:-warn}
      - N8N_METRICS=true
      - N8N_DISABLE_PRODUCTION_MAIN_PROCESS=false
      - EXECUTIONS_PROCESS=main
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
    ports:
      - "${N8N_PORT:-5678}:5678"
    volumes:
      - n8n_data:/home/node/.n8n
      - ./backups:/backups
    networks:
      - n8n_net
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - /var/log/nginx:/var/log/nginx
    networks:
      - n8n_net
    depends_on:
      - n8n

volumes:
  postgres_data:
  n8n_data:

networks:
  n8n_net:
    driver: bridge
EOF

# Create nginx.conf
cat > "$APP_DIR/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream n8n {
        server n8n:5678;
    }
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
    
    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' wss: https:; font-src 'self'; worker-src 'self' blob:;" always;
    
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }
    
    server {
        listen 443 ssl http2;
        server_name _;
        
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        
        client_max_body_size 10M;
        
        # Auth endpoints rate limiting
        location /rest/login {
            limit_req zone=login burst=3 nodelay;
            proxy_pass http://n8n;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Webhook endpoints
        location /webhook {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://n8n;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300;
            proxy_connect_timeout 300;
            proxy_send_timeout 300;
        }
        
        # Main application
        location / {
            limit_req zone=api burst=10 nodelay;
            proxy_pass http://n8n;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }
    }
}
EOF

# Create start.sh
cat > "$APP_DIR/start.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

CONFIG_DIR="/opt/n8n"
cd "$CONFIG_DIR"

# Generate secrets if missing
if [[ ! -f .env ]]; then
    echo "Generating configuration..."
    
    DB_PASSWORD=$(openssl rand -base64 32)
    N8N_PASSWORD=$(openssl rand -base64 16)
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    cat > .env << EOL
DB_PASSWORD=${DB_PASSWORD}
N8N_USER=${N8N_USER:-admin}
N8N_PASSWORD=${N8N_PASSWORD}
N8N_HOST=${N8N_HOST:-localhost}
N8N_PORT=${N8N_PORT:-5678}
TZ=${TZ:-UTC}
N8N_LOG_LEVEL=${N8N_LOG_LEVEL:-warn}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOL
    
    chmod 600 .env
    echo "Generated credentials saved to .env"
fi

# Generate self-signed SSL if missing
if [[ ! -f ssl/cert.pem ]]; then
    echo "Generating self-signed SSL certificate..."
    mkdir -p ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/key.pem -out ssl/cert.pem \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${N8N_HOST:-localhost}" \
        2>/dev/null
    chmod 600 ssl/key.pem
fi

# Check Docker availability
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker not installed"
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    echo "ERROR: docker-compose not installed"
    exit 1
fi

# Pull images and start services
echo "Starting n8n stack..."
docker-compose pull
docker-compose up -d

# Wait for services
echo "Waiting for services to start..."
timeout 60 bash -c 'until docker-compose ps | grep -q "Up.*healthy"; do sleep 2; done' || {
    echo "ERROR: Services failed to start properly"
    docker-compose logs
    exit 1
}

echo "n8n is running at https://${N8N_HOST:-localhost}"
echo "Default credentials are in .env file"
EOF

# Create backup.sh
cat > "$APP_DIR/backup.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/n8n/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

cd /opt/n8n

# Database backup
echo "Backing up PostgreSQL database..."
docker-compose exec -T postgres pg_dump -U n8n -d n8n | gzip > "${BACKUP_DIR}/db_${TIMESTAMP}.sql.gz"

# n8n data backup
echo "Backing up n8n data..."
docker-compose exec -T n8n tar czf - /home/node/.n8n > "${BACKUP_DIR}/n8n_data_${TIMESTAMP}.tar.gz"

# Keep only last 7 backups
find "${BACKUP_DIR}" -name "*.gz" -mtime +7 -delete

echo "Backup completed: ${TIMESTAMP}"
EOF

# Make scripts executable
chmod +x "$APP_DIR/start.sh" "$APP_DIR/backup.sh"

# Set ownership
log "Setting permissions..."
chown -R $AMP_USER:$AMP_USER "$TEMPLATE_DIR"
chown -R $AMP_USER:$AMP_USER "$APP_DIR"

# Setup firewall if ufw exists
if command -v ufw >/dev/null 2>&1; then
    log "Configuring firewall..."
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
fi

# Setup log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/n8n << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    notifempty
    create 644 www-data www-data
    postrotate
        docker-compose -f /opt/n8n/docker-compose.yml exec nginx nginx -s reload >/dev/null 2>&1 || true
    endscript
}
EOF

# Setup backup cron
log "Setting up automated backups..."
echo "0 2 * * * $AMP_USER /opt/n8n/backup.sh" >> /etc/crontab

# Restart AMP to pick up new templates
log "Restarting AMP..."
if systemctl is-active amp >/dev/null 2>&1; then
    systemctl restart amp
elif systemctl is-active ampinstmgr >/dev/null 2>&1; then
    systemctl restart ampinstmgr
else
    warn "Could not restart AMP automatically - please restart manually"
fi

log "Installation complete!"
echo
echo "Next steps:"
echo "1. Open AMP web interface"
echo "2. Create new instance -> Generic Application -> n8n"
echo "3. Configure hostname and start the instance"
echo "4. Access n8n at https://your-hostname"
echo
echo "Generated files:"
echo "- Templates: $TEMPLATE_DIR/n8n*"
echo "- Application: $APP_DIR/"
echo "- Backups will be stored in: $APP_DIR/backups/"
