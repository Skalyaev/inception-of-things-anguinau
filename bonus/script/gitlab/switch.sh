#!/usr/bin/env bash
set -euo pipefail

GITLAB_NAMESPACE="$1"
GITLAB_HOST="$2"
GITLAB_URI="$3"
APP_NAMESPACE="$4"
APP_NAME="$5"

GITLAB_GROUP="${GITLAB_URI%%/*}"
GITLAB_PROJECT="${GITLAB_URI##*/}"

BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RST='\033[0m'

log() {
  local color="$1"
  shift
  echo -e "[${color}gitlab/switch$RST] $*"
}
info() { log "$BLUE" "$*"; }
success() { log "$GREEN" "$*"; }
error() { log "$RED" "$*"; }

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then

  KUBECTL+=(--context "$KUBE_CONTEXT")
fi
k() { "${KUBECTL[@]}" "$@"; }

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
  exit 1
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
  QUERY+="name: 'switch-automation',"
  QUERY+=" scopes: ['api', 'write_repository', 'read_repository'],"
  QUERY+=" user: u,"
  QUERY+=" expires_at: 365.days.from_now);"
  QUERY+=" raw = SecureRandom.hex(20);"
  QUERY+=" t.set_token(raw); t.save!; puts raw\""

  TOKEN="$(k -n "$GITLAB_NAMESPACE" exec 'deploy/gitlab-toolbox' \
    -- bash -lc "$QUERY" 2>'/dev/null' || echo "")"

  if [[ -n "$TOKEN" ]]; then

    k -n "$GITLAB_NAMESPACE" create secret generic "$SECRET_NAME" \
      --from-literal="token=$TOKEN" \
      --dry-run=client -o yaml | k apply -f - >/dev/null
  fi
fi
if [[ -z "$TOKEN" ]]; then

  error "failed to generate personal access token"
  exit 1
fi
success "personal access token ready"

#============================# Update application version
URL="https://oauth2:${TOKEN}@${NODE_IP}"
URL+=":${NODE_PORT}/${GITLAB_URI}.git"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DST="$TMP_DIR/clone"

GIT_SSL_NO_VERIFY=true git -c \
  http.extraHeader="Host: $GITLAB_HOST" \
  clone -q "$URL" "$DST"

pushd "$DST" >'/dev/null'
FILE='playground/deployment.yaml'

TAG="$(grep -Eo 'wil42/playground:v[0-9]+' "$FILE" |
  head -n1 | sed -E 's#.*:(v[0-9]+)$#\1#')"

if [[ "$TAG" == 'v1' ]]; then
  NEW_TAG='v2'

elif [[ "$TAG" == 'v2' ]]; then
  NEW_TAG='v1'
else
  error "invalid current tag '$TAG'"
  exit 1
fi
info "switching from $TAG to $NEW_TAG"

sed -i.bak "s#wil42/playground:v[0-9]\\+#wil42/playground:${NEW_TAG}#" "$FILE"
rm -f "${FILE}.bak"

git config user.name 'root'
git config user.email 'root@gitlab.local'
git config http.extraHeader "Host: $GITLAB_HOST"
git config http.sslVerify false

git add "$FILE"
git commit -qm "switch playground image to ${NEW_TAG}"

info "pushing changes"
git push -q 'origin' 'main'

popd >'/dev/null'
success "application version switched to '$NEW_TAG'"

#============================# Trigger ArgoCD refresh
DATA='{"metadata":{"annotations":'
DATA+='{"argocd.argoproj.io/refresh":"hard"}}}'

k -n "$APP_NAMESPACE" patch application \
  "$APP_NAME" --type merge -p "$DATA"

#============================#
success 'done'
