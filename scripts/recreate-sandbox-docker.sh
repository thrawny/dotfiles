#!/usr/bin/env bash
set -euo pipefail

vm_name="${SANDBOX_DOCKER_VM:-sandbox-docker}"
image="${SANDBOX_DOCKER_IMAGE:-images:ubuntu/noble/cloud}"
cpu="${SANDBOX_DOCKER_CPU:-8}"
memory="${SANDBOX_DOCKER_MEMORY:-4GiB}"
ipv4_address="${SANDBOX_DOCKER_IPV4:-10.0.100.10}"

if incus info "$vm_name" >/dev/null 2>&1; then
  incus delete -f "$vm_name"
fi

incus launch "$image" "$vm_name" --vm \
  -c limits.cpu="$cpu" \
  -c limits.memory="$memory" \
  -c boot.autostart=true \
  -c boot.autostart.delay=10

incus config device override "$vm_name" eth0 ipv4.address="$ipv4_address"
incus restart "$vm_name"

incus exec "$vm_name" -- cloud-init status --wait

incus exec "$vm_name" -- sh -lc '
  set -euo pipefail
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  mkdir -p /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375
EOF
  systemctl daemon-reload
  systemctl enable --now docker
'

DOCKER_HOST="tcp://${ipv4_address}:2375" docker version >/dev/null

echo "$vm_name ready: DOCKER_HOST=tcp://${ipv4_address}:2375"
