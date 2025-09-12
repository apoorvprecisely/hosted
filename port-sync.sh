#!/bin/bash

# Gluetun-qBittorrent Port Sync Script
# This script monitors the Gluetun forwarded port and updates qBittorrent accordingly

set -euo pipefail

# Configuration
QBITTORRENT_HOST="${QBITTORRENT_HOST:-localhost}"
QBITTORRENT_PORT="${QBITTORRENT_PORT:-8080}"
QBITTORRENT_USER="${QBITTORRENT_USER:-admin}"
QBITTORRENT_PASS="${QBITTORRENT_PASS:-adminpass}"
PORT_FILE="${PORT_FILE:-/tmp/gluetun/forwarded_port}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to get qBittorrent session cookie
get_qbt_cookie() {
    local cookie_jar="/tmp/qbt_cookie.txt"
    
    # Login to qBittorrent
    if curl -s -c "$cookie_jar" \
        --data "username=${QBITTORRENT_USER}&password=${QBITTORRENT_PASS}" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/auth/login" > /dev/null; then
        echo "$cookie_jar"
        return 0
    else
        error "Failed to login to qBittorrent"
        return 1
    fi
}

# Function to get current qBittorrent listening port
get_qbt_port() {
    local cookie_jar="$1"
    
    curl -s -b "$cookie_jar" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/app/preferences" | \
        grep -o '"listen_port":[0-9]*' | \
        cut -d':' -f2
}

# Function to set qBittorrent listening port
set_qbt_port() {
    local cookie_jar="$1"
    local new_port="$2"
    
    curl -s -b "$cookie_jar" \
        --data "json={\"listen_port\":${new_port}}" \
        "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/app/setPreferences"
}

# Function to wait for qBittorrent to be ready
wait_for_qbittorrent() {
    log "Waiting for qBittorrent to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --connect-timeout 5 "http://${QBITTORRENT_HOST}:${QBITTORRENT_PORT}/api/v2/app/version" > /dev/null 2>&1; then
            log "qBittorrent is ready!"
            return 0
        fi
        
        warn "qBittorrent not ready yet (attempt $attempt/$max_attempts). Waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    error "qBittorrent failed to become ready after $max_attempts attempts"
    return 1
}

# Function to wait for Gluetun port file
wait_for_port_file() {
    log "Waiting for Gluetun port file..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ -f "$PORT_FILE" ] && [ -s "$PORT_FILE" ]; then
            log "Gluetun port file is ready!"
            return 0
        fi
        
        warn "Gluetun port file not ready yet (attempt $attempt/$max_attempts). Waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    error "Gluetun port file failed to become ready after $max_attempts attempts"
    return 1
}

# Main monitoring loop
main() {
    log "Starting Gluetun-qBittorrent Port Sync Script"
    log "Configuration:"
    log "  qBittorrent: ${QBITTORRENT_HOST}:${QBITTORRENT_PORT}"
    log "  Port file: ${PORT_FILE}"
    log "  Check interval: ${CHECK_INTERVAL}s"
    
    # Wait for services to be ready
    wait_for_qbittorrent
    wait_for_port_file
    
    local last_port=""
    
    while true; do
        # Check if port file exists and is readable
        if [ ! -f "$PORT_FILE" ]; then
            warn "Port file $PORT_FILE does not exist. Waiting..."
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Read the current forwarded port
        local current_port
        if ! current_port=$(cat "$PORT_FILE" 2>/dev/null | tr -d '\n\r' | grep -o '[0-9]*'); then
            warn "Failed to read port from $PORT_FILE"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Validate port number
        if [ -z "$current_port" ] || [ "$current_port" -lt 1024 ] || [ "$current_port" -gt 65535 ]; then
            warn "Invalid port number: '$current_port'"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Check if port has changed
        if [ "$current_port" != "$last_port" ]; then
            log "New forwarded port detected: $current_port"
            
            # Get qBittorrent session cookie
            if cookie_jar=$(get_qbt_cookie); then
                # Get current qBittorrent port
                local qbt_port
                if qbt_port=$(get_qbt_port "$cookie_jar"); then
                    log "Current qBittorrent port: $qbt_port"
                    
                    if [ "$qbt_port" != "$current_port" ]; then
                        log "Updating qBittorrent port to: $current_port"
                        
                        if set_qbt_port "$cookie_jar" "$current_port"; then
                            log "Successfully updated qBittorrent port to $current_port"
                            last_port="$current_port"
                        else
                            error "Failed to update qBittorrent port"
                        fi
                    else
                        log "qBittorrent port is already correct: $current_port"
                        last_port="$current_port"
                    fi
                else
                    error "Failed to get current qBittorrent port"
                fi
                
                # Clean up cookie file
                rm -f "$cookie_jar"
            else
                error "Failed to authenticate with qBittorrent"
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Handle signals gracefully
trap 'log "Received signal, shutting down..."; exit 0' SIGTERM SIGINT

# Run main function
main "$@"

