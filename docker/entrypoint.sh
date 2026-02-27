#!/bin/bash
# entrypoint.sh — IT-Stack redis container entrypoint
set -euo pipefail

echo "Starting IT-Stack REDIS (Module 04)..."

# Source any environment overrides
if [ -f /opt/it-stack/redis/config.env ]; then
    # shellcheck source=/dev/null
    source /opt/it-stack/redis/config.env
fi

# Execute the upstream entrypoint or command
exec "$$@"
