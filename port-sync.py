#!/usr/bin/env python3
"""
Sync ProtonVPN forwarded port to qBittorrent
Reads forwarded port from transmission-openvpn logs and updates qBittorrent
"""
import os
import time
import requests
import subprocess
import sys

QBITTORRENT_HOST = os.getenv('QBITTORRENT_HOST', 'localhost')
QBITTORRENT_PORT = os.getenv('QBITTORRENT_PORT', '8080')
QBITTORRENT_USER = os.getenv('QBITTORRENT_USER', 'admin')
QBITTORRENT_PASS = os.getenv('QBITTORRENT_PASS', 'adminadmin')
CHECK_INTERVAL = int(os.getenv('CHECK_INTERVAL', '60'))

def get_forwarded_port():
    """Get the forwarded port from transmission-openvpn logs"""
    try:
        result = subprocess.run(
            ['docker', 'logs', 'transmission-openvpn', '--tail', '50'],
            capture_output=True,
            text=True
        )
        
        # Look for the forwarded port in logs
        import re
        for line in reversed(result.stdout.split('\n')):
            if 'forwarded port is:' in line.lower():
                # Extract port number after "forwarded port is:"
                match = re.search(r'forwarded port is:\s*(\d+)', line, re.IGNORECASE)
                if match:
                    port = int(match.group(1))
                    # Validate port range
                    if 1024 <= port <= 65535:
                        return port
        return None
    except Exception as e:
        print(f"Error getting forwarded port: {e}")
        return None

def login_qbittorrent():
    """Login to qBittorrent and return session"""
    session = requests.Session()
    url = f"http://{QBITTORRENT_HOST}:{QBITTORRENT_PORT}/api/v2/auth/login"
    
    try:
        response = session.post(url, data={
            'username': QBITTORRENT_USER,
            'password': QBITTORRENT_PASS
        }, timeout=10)
        
        if response.status_code == 200 and response.text == 'Ok.':
            print(f"✓ Logged in to qBittorrent at {QBITTORRENT_HOST}:{QBITTORRENT_PORT}")
            return session
        else:
            print(f"✗ Login failed: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        print(f"✗ Connection error: {e}")
        return None

def get_current_port(session):
    """Get current listening port from qBittorrent"""
    url = f"http://{QBITTORRENT_HOST}:{QBITTORRENT_PORT}/api/v2/app/preferences"
    try:
        response = session.get(url, timeout=10)
        if response.status_code == 200:
            prefs = response.json()
            return prefs.get('listen_port')
        return None
    except Exception as e:
        print(f"Error getting current port: {e}")
        return None

def set_qbittorrent_port(session, port):
    """Set qBittorrent listening port"""
    url = f"http://{QBITTORRENT_HOST}:{QBITTORRENT_PORT}/api/v2/app/setPreferences"
    
    try:
        import json
        # qBittorrent expects JSON string as form data
        preferences = json.dumps({
            'listen_port': port,
            'upnp': False,
            'random_port': False
        })
        
        response = session.post(url, data={'json': preferences}, timeout=10)
        
        if response.status_code == 200:
            return True
        else:
            print(f"✗ Failed to set port: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"✗ Error setting port: {e}")
        return False

def main():
    print("=" * 60)
    print("ProtonVPN → qBittorrent Port Sync Service")
    print("=" * 60)
    print(f"qBittorrent: {QBITTORRENT_HOST}:{QBITTORRENT_PORT}")
    print(f"Check interval: {CHECK_INTERVAL}s")
    print("=" * 60)
    
    last_port = None
    
    while True:
        try:
            # Get forwarded port from ProtonVPN
            forwarded_port = get_forwarded_port()
            
            if not forwarded_port:
                print("⏳ Waiting for ProtonVPN port forwarding...")
                time.sleep(CHECK_INTERVAL)
                continue
            
            # Check if port changed
            if forwarded_port == last_port:
                print(f"✓ Port unchanged: {forwarded_port}")
                time.sleep(CHECK_INTERVAL)
                continue
            
            print(f"\n🔄 New forwarded port detected: {forwarded_port}")
            
            # Login to qBittorrent
            session = login_qbittorrent()
            if not session:
                print("⏳ Waiting for qBittorrent to be ready...")
                time.sleep(CHECK_INTERVAL)
                continue
            
            # Get current port
            current_port = get_current_port(session)
            print(f"Current qBittorrent port: {current_port}")
            
            if current_port == forwarded_port:
                print(f"✓ Port already set correctly: {forwarded_port}")
                last_port = forwarded_port
                time.sleep(CHECK_INTERVAL)
                continue
            
            # Update port
            print(f"📝 Updating qBittorrent port to {forwarded_port}...")
            if set_qbittorrent_port(session, forwarded_port):
                print(f"✅ Successfully updated port to {forwarded_port}")
                last_port = forwarded_port
            else:
                print(f"❌ Failed to update port")
            
            time.sleep(CHECK_INTERVAL)
            
        except KeyboardInterrupt:
            print("\n\n👋 Shutting down...")
            sys.exit(0)
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
            time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()

