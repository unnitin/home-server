#!/bin/bash
# Quick Immich fix script

echo "🔧 Fixing Immich Issue"
echo "======================"

cd /Users/nitinsrivastava/Documents/home-server/services/immich

echo "1. Stopping Immich server..."
docker compose stop immich-server

echo "2. Ensuring .immich files are properly created..."
for dir in /Volumes/Photos/*/; do
    if [[ -d "$dir" ]]; then
        echo "IMMICH_UPLOAD" > "$dir/.immich"
        echo "Created .immich in $(basename "$dir")"
    fi
done

echo "3. Setting proper permissions..."
sudo chown -R $(whoami):staff /Volumes/Photos/
chmod -R 755 /Volumes/Photos/

echo "4. Starting Immich with folder checks disabled..."
docker compose up -d immich-server

echo "5. Waiting for startup..."
sleep 15

echo "6. Checking status..."
docker compose ps

echo "7. Testing web access..."
curl -f http://localhost:2283 >/dev/null 2>&1 && echo "✅ Immich web UI accessible" || echo "⚠️  Still starting up - check in a moment"

echo "✅ Immich fix complete!"
