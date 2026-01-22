#!/usr/bin/env bash
set -euo pipefail

GITLAB_NAMESPACE="$1"
GITLAB_HOST="$2"
GITLAB_URI="$3"

GITLAB_GROUP="${GITLAB_URI%%/*}"
GITLAB_PROJECT="${GITLAB_URI##*/}"

GREEN='\033[1;32m'
RED='\033[1;31m'
RST='\033[0m'

log() {
  local color="$1"
  shift
  echo -e "[${color}gitlab/down$RST] $*"
}
success() { log "$GREEN" "$*"; }
error() { log "$RED" "$*"; }

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then

  KUBECTL+=(--context "$KUBE_CONTEXT")
fi
k() { "${KUBECTL[@]}" "$@"; }

delete() {
  local url="$1"
  local token="$2"

  curl -kfsS \
    -H "PRIVATE-TOKEN: $token" \
    -H "Host: $GITLAB_HOST" \
    -X 'DELETE' \
    "$url"
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

#============================# Personal Access Token generation
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

  QUERY="gitlab-rails runner \"require 'securerandom';"
  QUERY+=" u = User.find_by_username('root');"
  QUERY+=" t = PersonalAccessToken.new("
  QUERY+="name: 'cleanup',"
  QUERY+=" scopes: ['api'],"
  QUERY+=" user: u,"
  QUERY+=" expires_at: 1.day.from_now);"
  QUERY+=" raw = SecureRandom.hex(20);"
  QUERY+=" t.set_token(raw); t.save!; puts raw\""

  TOKEN="$(k -n "$GITLAB_NAMESPACE" \
    exec 'deploy/gitlab-toolbox' \
    -- bash -lc "$QUERY" 2>'/dev/null' || echo "")"
fi
if [[ -z "$TOKEN" ]]; then

  error "failed to generate personal access token"
  exit 0
fi
success "personal access token ready"

#============================# Project deletion
URL="$(echo -n "$GITLAB_GROUP/$GITLAB_PROJECT" |
  sed 's,/,\%2F,g')"

URL="$GITLAB_URL/api/v4/projects/$URL"

JSON="$(curl -ksS -H "PRIVATE-TOKEN: $TOKEN" \
  -H "Host: $GITLAB_HOST" "$URL")"

PROJECT_ID="$(extract "$JSON")"
if [[ -z "$PROJECT_ID" ]]; then

  error "project '$GITLAB_PROJECT' not found"
else
  delete "$GITLAB_URL/api/v4/projects/$PROJECT_ID" "$TOKEN"
  success "project '$GITLAB_PROJECT' deleted"
fi

#============================# Group deletion
URL="$GITLAB_URL/api/v4/groups/$GITLAB_GROUP"

JSON="$(curl -ksS -H "PRIVATE-TOKEN: $TOKEN" \
  -H "Host: $GITLAB_HOST" "$URL")"

GROUP_ID="$(extract "$JSON")"
if [[ -z "$GROUP_ID" ]]; then

  error "group '$GITLAB_GROUP' not found"
else
  delete "$GITLAB_URL/api/v4/groups/$GROUP_ID" "$TOKEN"
  success "group '$GITLAB_GROUP' deleted"
fi

#============================#
success 'done'
