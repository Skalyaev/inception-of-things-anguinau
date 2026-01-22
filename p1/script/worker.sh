#!/usr/bin/env bash
set -euo pipefail

SERVER_IP=$1
WORKER_IP=$2

#============================#
echo 'Waiting for K3s server...'

export K3S_TOKEN_FILE='/vagrant/server-token'
export K3S_URL="https://$SERVER_IP:6443"

while [ ! -f "$K3S_TOKEN_FILE" ]; do sleep 1; done

until curl -k -s "$K3S_URL/ping" | grep -q 'pong'; do
  sleep 1
done

#============================#
echo 'Installing K3s agent...'

AWK='$0 ~ ip {print $2; exit}'
IFACE=$(ip -o addr show | awk -v ip="$WORKER_IP" "$AWK")

export INSTALL_K3S_EXEC="--flannel-iface=$IFACE"

curl -sfL 'https://get.k3s.io' | sh -

#============================#
echo 'K3s agent setup complete'
