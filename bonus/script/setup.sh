#!/usr/bin/env bash
set -euo pipefail

CLUSTER="$1"

DIRNAME="$(dirname "$0")"
BASE_DIR="$(cd "$DIRNAME/.." && pwd)"

BLUE='\033[1;34m'
GREEN='\033[1;32m'
RST='\033[0m'

log() {
  local color="$1"
  shift
  echo -e "[${color}setup$RST] $*"
}
info() { log "$BLUE" "$*"; }
success() { log "$GREEN" "$*"; }

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then

  KUBECTL+=(--context "$KUBE_CONTEXT")
fi
k() { "${KUBECTL[@]}" "$@"; }

#============================# Docker
if ! command -v 'docker' &>'/dev/null'; then

  info 'docker not found, installing.'

  sudo apt-get update -y
  sudo apt-get install -y 'ca-certificates'
  sudo apt-get install -y 'curl'

  sudo install -m 0755 -d '/etc/apt/keyrings'

  SRC='https://download.docker.com/linux/debian'
  DST='/etc/apt/keyrings/docker.asc'

  sudo curl -fsSL "$SRC/gpg" -o "$DST"
  sudo chmod a+r "$DST"

  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. '/etc/os-release' && echo "$VERSION_CODENAME")"

  ENTRY="deb [arch=$ARCH signed-by=$DST] $SRC $CODENAME stable"
  SOURCE_LIST='/etc/apt/sources.list.d/docker.list'

  echo "$ENTRY" | sudo tee "$SOURCE_LIST" >'/dev/null'
  sudo apt-get update -y

  sudo apt-get install -y 'docker-ce'
  sudo apt-get install -y 'docker-ce-cli'
  sudo apt-get install -y 'containerd.io'
  sudo apt-get install -y 'docker-buildx-plugin'
  sudo apt-get install -y 'docker-compose-plugin'

  sudo usermod -aG 'docker' "$USER"
  exec sg docker "$0 \"$@\""
fi
if ! docker info &>'/dev/null'; then

  info 'docker not running, starting.'

  sudo systemctl start 'docker'
fi
success 'docker ready'

#============================# Kubectl
if ! command -v 'kubectl' &>'/dev/null'; then

  info 'kubectl not found, installing.'

  VERSION="$(curl -fsSL 'https://dl.k8s.io/release/stable.txt')"

  SRC="https://dl.k8s.io/release/"
  SRC+="$VERSION/bin/linux/amd64/kubectl"

  DST='/usr/local/bin/kubectl'

  curl -fsSLo 'kubectl' "$SRC"
  sudo install -o 'root' -g 'root' -m '0755' 'kubectl' "$DST"
  rm -f 'kubectl'
fi
success 'kubectl ready'

#============================# K3d
if ! command -v 'k3d' &>'/dev/null'; then

  info 'k3d not found, installing.'

  SRC='https://raw.githubusercontent.com'
  SRC+='/k3d-io/k3d/main/install.sh'

  curl -s "$SRC" | bash
fi
success 'k3d ready'

#============================# K3s cluster
CLUSTER_LINE="$(k3d cluster list --no-headers |
  awk -v c="$CLUSTER" '$1 == c {print; exit}')"

if [[ -z "$CLUSTER_LINE" ]]; then

  info "cluster '$CLUSTER' not found, creating"

  PORT='8888:8888@loadbalancer'
  k3d cluster create "$CLUSTER" --agents '1' --port "$PORT"
else
  CLUSTER_STATUS="$(echo "$CLUSTER_LINE" | awk '{print $2}')"

  if [[ "$CLUSTER_STATUS" != 'running' ]]; then

    k3d cluster start "$CLUSTER"
  fi
fi
k wait --for='condition=ready' node --all

success "cluster '$CLUSTER' ready"

#============================# ArgoCD
ARGOCD_DIR="$BASE_DIR/k8s/argocd"

INSTALLED=1

if ! k get ns 'argocd' &>'/dev/null'; then

  INSTALLED=0
else
  if ! k -n 'argocd' \
    get deploy 'argocd-server' &>'/dev/null'; then

    INSTALLED=0
  fi
fi
if [[ $INSTALLED -eq 0 ]]; then

  info 'argocd not found, installing.'

  URL='https://raw.githubusercontent.com/argoproj/argo-cd'
  URL+='/stable/manifests/install.yaml'

  k apply -f "$ARGOCD_DIR/namespace.yaml"

  k apply -n 'argocd' -f "$URL"
fi
k -n 'argocd' rollout status 'deploy/argocd-server'
k -n 'argocd' rollout status 'deploy/argocd-repo-server'
k -n 'argocd' rollout status \
  'statefulset/argocd-application-controller'

APP_TEMPLATE="$ARGOCD_DIR/application.yaml"
sed \
  -e "s|\$(GITLAB_URL)|$GITLAB_URL|g" \
  -e "s|\$(GITLAB_PROJECT)|$GITLAB_PROJECT|g" \
  "$APP_TEMPLATE" | k apply -f -

success 'argocd ready'

#============================# Git
if ! command -v 'git' &>'/dev/null'; then

  info 'git not found, installing.'

  sudo apt-get update -y
  sudo apt-get install -y 'git'
fi
success 'git ready'

#============================# Helm
if ! command -v 'helm' &>'/dev/null'; then

  info 'helm not found, installing.'

  SRC='https://raw.githubusercontent.com'
  SRC+='/helm/helm/main/scripts/get-helm-3'

  curl -fsSL "$SRC" | bash
fi
success 'helm ready'

#============================# GitLab
GITLAB_DIR="$BASE_DIR/k8s/gitlab"

if ! k get ns 'gitlab' &>'/dev/null'; then

  k apply -f "$GITLAB_DIR/namespace.yaml"
fi
if ! helm --kube-context "$KUBE_CONTEXT" \
  -n 'gitlab' status 'gitlab' &>'/dev/null'; then

  info 'gitlab not found, installing.'

  helm repo add gitlab 'https://charts.gitlab.io'
  helm repo update

  k apply -f "$GITLAB_DIR/secret.yaml"

  SRC="$GITLAB_DIR/values.yaml"

  helm --kube-context "$KUBE_CONTEXT" \
    install 'gitlab' 'gitlab/gitlab' -n 'gitlab' -f "$SRC"
fi
if ! grep -q '^127.0.0.1\s\+gitlab\.local' '/etc/hosts'; then

  echo '127.0.0.1 gitlab.local' |
    sudo tee -a '/etc/hosts' >/dev/null

  success 'added gitlab.local to /etc/hosts'
fi
k -n 'gitlab' rollout status 'deploy/gitlab-webservice-default'

success 'gitlab ready'

#============================#
success 'done'
