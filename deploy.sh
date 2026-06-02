#!/bin/bash
# Podman Deployment Script
set -e  # Exit on error

echo "Deploying Street Scissors with Podman..."

# Create network if not exists
podman network exists caddy_net || podman network create caddy_net

# Create volumes if not exists
podman volume exists sqlite_data || podman volume create sqlite_data
podman volume exists caddy_data || podman volume create caddy_data
podman volume exists caddy_config || podman volume create caddy_config

# Build Web Image
echo "Building web image..."
podman build --no-cache -t streetscissors_web -f Dockerfile .

# Stop and Remove old containers
echo "Stopping old containers..."
# Use || true to ignore error if containers don't exist
podman rm -f web caddy 2>/dev/null || true

# Run Web Container
echo "Starting web container..."
podman run -d --name web --restart always \
  -e PHX_SERVER=true \
  --env-file .env \
  -v sqlite_data:/data:Z \
  -v ./content:/app/content:Z \
  --network host \
  streetscissors_web

# Run Caddy Container
echo "Starting caddy container..."
# Using host binding for ports.
podman run -d --name caddy --restart always \
  --network host \
  -v ./Caddyfile:/etc/caddy/Caddyfile:Z \
  -v caddy_data:/data:Z \
  -v caddy_config:/config:Z \
  docker.io/caddy:latest

echo "Waiting for web connection..."
sleep 5
echo "Running migrations..."
podman exec -e RELEASE_NODE=migrator@$(hostname) web /app/bin/web eval "Web.Release.migrate"

echo "Deployment Complete!"
podman ps
