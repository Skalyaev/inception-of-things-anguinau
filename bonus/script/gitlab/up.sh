#!/usr/bin/env bash
set -euo pipefail

GITLAB_NAMESPACE="$1"
GITLAB_HOST="$2"
GITLAB_URI="$3"

GITLAB_GROUP="${GITLAB_URI%%/*}"
GITLAB_PROJECT="${GITLAB_URI##*/}"

DIRNAME="$(dirname "$0")"
BASE_DIR="$(cd "$DIRNAME/../.." && pwd)"

GREEN='\033[1;32m'
RED='\033[1;31m'
RST='\033[0m'

log() {
  local color="$1"
  shift
  echo -e "[${color}gitlab/up$RST] $*"
}
success() { log "$GREEN" "$*"; }
error() { log "$RED" "$*"; }

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then

  KUBECTL+=(--context "$KUBE_CONTEXT")
fi
k() { "${KUBECTL[@]}" "$@"; }

post() {
  local url="$1"
  local data="$2"
  local token="$3"

  curl -kfsS \
    -H 'Content-Type: application/json' \
    -H "PRIVATE-TOKEN: $token" \
    -H "Host: $GITLAB_HOST" \
    -X 'POST' -d "$data" "$url"
}
extract() {
  local json="$1"

  local to_sed='s/.*"id"[[:space:]]*:'
  local to_sed+='[[:space:]]*\([0-9][0-9]*\).*/\1/p'

  printf '%s' "$json" | sed -n "$to_sed" | head -n1
}

JSONPATH='{.items[0].status.addresses'
JSONPATH+='[?(@.type=="InternalIP")].address}'

NODE_IP="$(k get nodes -o jsonpath="$JSONPATH")"

SVC='gitlab-nginx-ingress-controller'
JSONPATH='{.spec.ports[?(@.name=="https")].nodePort}'

NODE_PORT="$(k -n "$GITLAB_NAMESPACE" \
  get svc "$SVC" -o jsonpath="$JSONPATH")"

GITLAB_URL="https://${NODE_IP}:${NODE_PORT}"

#============================# Checks
if ! k get namespace "$GITLAB_NAMESPACE" &>'/dev/null'; then

  error "namespace '$GITLAB_NAMESPACE' not found"
  exit 1
fi

#============================# Personal Access Token
k -n "$GITLAB_NAMESPACE" rollout status \
  'deploy/gitlab-toolbox' 2>/dev/null || {

  error "GitLab toolbox not ready"
  exit 0
}
SECRET_NAME='gitlab-automation-token'
TOKEN=''

if k -n "$GITLAB_NAMESPACE" \
  get secret "$SECRET_NAME" &>'/dev/null'; then

  TOKEN="$(k -n "$GITLAB_NAMESPACE" get secret "$SECRET_NAME" \
    -o jsonpath='{.data.token}' 2>'/dev/null' |
    base64 -d 2>'/dev/null' || true)"
fi
if [[ -z "$TOKEN" ]]; then

  k -n "$GITLAB_NAMESPACE" \
    rollout status 'deploy/gitlab-toolbox'

  QUERY="gitlab-rails runner \"require 'securerandom';"
  QUERY+=" u = User.find_by_username('root');"
  QUERY+=" t = PersonalAccessToken.new("
  QUERY+="name: 'automation',"
  QUERY+=" scopes: ['api', 'write_repository', "
  QUERY+="'read_repository'],"
  QUERY+=" user: u,"
  QUERY+=" expires_at: 365.days.from_now);"
  QUERY+=" raw = SecureRandom.hex(20);"
  QUERY+=" t.set_token(raw); t.save!; puts raw\""

  TOKEN="$(k -n "$GITLAB_NAMESPACE" \
    exec 'deploy/gitlab-toolbox' \
    -- bash -lc "$QUERY" 2>'/dev/null')"

  if [[ -z "$TOKEN" ]]; then

    error "failed to generate personal access token"
    exit 1
  fi
  k -n "$GITLAB_NAMESPACE" \
    create secret generic "$SECRET_NAME" \
    --from-literal="token=$TOKEN" \
    --dry-run=client -o yaml | k apply -f - >/dev/null

  success "personal access token generated"
else
  success "personal access token loaded from secret"
fi

#============================# Group creation
URL="$GITLAB_URL/api/v4/groups/$GITLAB_GROUP"

JSON="$(curl -ksS -H "PRIVATE-TOKEN: $TOKEN" \
  -H "Host: $GITLAB_HOST" "$URL")"

GROUP_ID="$(extract "$JSON")"

if [[ -z "$GROUP_ID" ]]; then

  URL="$GITLAB_URL/api/v4/groups"

  DATA="{\"name\":\"$GITLAB_GROUP\""
  DATA+=",\"path\":\"$GITLAB_GROUP\""
  DATA+=",\"visibility\":\"public\"}"

  JSON="$(post "$URL" "$DATA" "$TOKEN")"
  GROUP_ID="$(extract "$JSON")"
fi
if [[ -z "$GROUP_ID" ]]; then

  error "failed to create group '$GITLAB_GROUP'"
  exit 1
fi
success "group created"

#============================# Project creation
URL="$(echo -n "$GITLAB_GROUP/$GITLAB_PROJECT" |
  sed 's,/,\%2F,g')"

URL="$GITLAB_URL/api/v4/projects/$URL"

JSON="$(curl -ksS -H "PRIVATE-TOKEN: $TOKEN" \
  -H "Host: $GITLAB_HOST" "$URL")"

PROJECT_ID="$(extract "$JSON")"

if [[ -z "$PROJECT_ID" ]]; then

  URL="$GITLAB_URL/api/v4/projects"

  DATA="{\"name\":\"$GITLAB_PROJECT\""
  DATA+=",\"namespace_id\":$GROUP_ID"
  DATA+=",\"visibility\":\"public\"}"

  JSON="$(post "$URL" "$DATA" "$TOKEN")"
  PROJECT_ID="$(extract "$JSON")"
fi
if [[ -z "$PROJECT_ID" ]]; then

  error "failed to create project '$GITLAB_URI'"
  exit 1
fi
success "project created"

#============================# Application upload
URL="https://oauth2:${TOKEN}@${NODE_IP}"
URL+=":${NODE_PORT}/${GITLAB_URI}.git"

if ! git ls-remote "$URL" HEAD &>/dev/null; then
  DEV_DIR="$BASE_DIR/k8s/dev"
  
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  
  cp -a "${DEV_DIR}/." "$TMP_DIR/"
  
  pushd "$TMP_DIR" >'/dev/null'
  git init -q
  git checkout -b 'main'
  
  git config user.name 'root'
  git config user.email 'root@gitlab.local'
  
  git config http.extraHeader "Host: $GITLAB_HOST"
  git config http.sslVerify false
  
  git add .
  git commit -qm 'initial commit'
  
  git remote add 'origin' "$URL"
  git push -u 'origin' 'main'
  
  popd >'/dev/null'
fi
success "application uploaded"

#============================#
success 'done'
