#!/bin/sh
# Fix ownership of named volume mount points that Docker creates as root.
# This must run as root before switching to the deploy user.
chown -R deploy:deploy /app/projects /home/deploy 2>/dev/null || true
exec su-exec deploy "$@"
