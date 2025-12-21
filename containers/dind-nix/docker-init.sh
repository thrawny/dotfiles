#!/bin/sh
set -e

echo "=== Docker-in-Docker Init ==="

# --- cgroup v2 nesting ---
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    echo "Configuring cgroup v2 nesting..."
    mkdir -p /sys/fs/cgroup/init
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi

# --- Mount filesystems if needed ---
if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security 2>/dev/null; then
    mount -t securityfs none /sys/kernel/security 2>/dev/null || true
fi

# --- Clean stale PIDs ---
find /run /var/run -iname 'docker*.pid' -delete 2>/dev/null || true
find /run /var/run -iname 'containerd*.pid' -delete 2>/dev/null || true

# --- Start dockerd with retry ---
echo "Starting dockerd..."
DOCKERD_READY=false

for attempt in 1 2 3 4 5; do
    echo "Attempt $attempt/5..."

    dockerd --storage-driver=vfs > /var/log/dockerd.log 2>&1 &
    DOCKERD_PID=$!

    # Wait for docker to be ready (up to 30 seconds)
    for i in $(seq 1 30); do
        if docker info > /dev/null 2>&1; then
            echo "Docker is ready!"
            DOCKERD_READY=true
            break 2
        fi
        sleep 1
    done

    # Not ready, kill and retry
    echo "dockerd not ready, retrying..."
    kill $DOCKERD_PID 2>/dev/null || true
    sleep 1
done

if [ "$DOCKERD_READY" = "false" ]; then
    echo "ERROR: Failed to start dockerd after 5 attempts"
    echo "=== dockerd logs ==="
    cat /var/log/dockerd.log
    exit 1
fi

# --- Execute command as dev user ---
if [ "$#" -gt 0 ]; then
    exec su - dev -c "cd /workspace && exec $*"
else
    exec su - dev -c "cd /workspace && exec zsh"
fi
