#!/usr/bin/env bash
set -euo pipefail

vm_name="${SANDBOX_DOCKER_VM:-sandbox-docker}"
image="${SANDBOX_DOCKER_IMAGE:-images:ubuntu/noble/cloud}"
cpu="${SANDBOX_DOCKER_CPU:-8}"
memory="${SANDBOX_DOCKER_MEMORY:-4GiB}"

incus_vm_ipv4() {
  incus list "$vm_name" --format=json 2>/dev/null \
    | jq -r '[.[0].state.network // {} | to_entries[] | select(.key != "lo" and .key != "docker0" and (.key | startswith("br-") | not) and (.key | startswith("veth") | not)) | .value.addresses[]? | select(.family == "inet") | .address] | first // empty'
}

if incus info "$vm_name" >/dev/null 2>&1; then
  incus delete -f "$vm_name"
fi

incus launch "$image" "$vm_name" --vm \
  -c limits.cpu="$cpu" \
  -c limits.memory="$memory" \
  -c boot.autostart=true \
  -c boot.autostart.delay=10

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

ipv4_address="$(incus_vm_ipv4)"
if [[ -z "$ipv4_address" ]]; then
  echo "Could not determine $vm_name IPv4 address." >&2
  exit 1
fi

DOCKER_HOST="tcp://${ipv4_address}:2375" docker version >/dev/null

echo "$vm_name ready: DOCKER_HOST=tcp://${ipv4_address}:2375"
