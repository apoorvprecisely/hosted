#!/bin/bash

# Build script for the port-sync service

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Change to the script directory
cd "$(dirname "$0")"

log "Building port-sync Docker image..."

# Build the Docker image
if docker build -f Dockerfile.port-sync -t port-sync:latest .; then
    log "Successfully built port-sync Docker image"
else
    error "Failed to build port-sync Docker image"
    exit 1
fi

log "Stopping existing port-sync container (if running)..."
docker-compose stop port-sync 2>/dev/null || true

log "Removing existing port-sync container (if exists)..."
docker-compose rm -f port-sync 2>/dev/null || true

log "Starting port-sync service..."
if docker-compose up -d port-sync; then
    log "Successfully started port-sync service"
    
    log "Checking service status..."
    sleep 5
    docker-compose ps port-sync
    
    log "Showing recent logs..."
    docker-compose logs --tail=20 port-sync
else
    error "Failed to start port-sync service"
    exit 1
fi

log "Port-sync service deployment completed!"
log "You can monitor logs with: docker-compose logs -f port-sync"

