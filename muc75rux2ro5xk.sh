#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-start}"
INSTALL_DIR='/usr/local/codem/private-zones/lsbx_muc75rux2ro5xk'
CONTROLLER_SCRIPT="$INSTALL_DIR/controller.sh"
ENV_FILE="$INSTALL_DIR/controller.env"

die() { echo "error: $*" >&2; exit 1; }

env_has_control_token() {
  [[ -f "$ENV_FILE" ]] || return 1
  (
    set +u
    source "$ENV_FILE" >/dev/null 2>&1 || exit 1
    [[ -n "${ZONE_CONTROL_PLANE_TOKEN:-}" ]]
  )
}

require_shared_store_root() {
  local expected='/usr/local/var/lib/codem/codem-sandbox' current
  [[ -n "$expected" ]] || return 0
  current="$(
    set +u
    source "$ENV_FILE" >/dev/null 2>&1 || exit 1
    printf '%s' "${DISPATCHER_STORE_ROOT:-}"
  )"
  [[ "$current" == "$expected" ]] || die "activated controller.env uses legacy StoreRoot $current; migrate its data into shared StoreRoot $expected, update DISPATCHER_STORE_ROOT, then rerun this installer"
}

require_shared_physical_device_root() {
  local expected='/usr/local/var/lib/codem/physical-device' current
  current="$(
    set +u
    source "$ENV_FILE" >/dev/null 2>&1 || exit 1
    printf '%s' "${PHYSICAL_DEVICE_DATA_ROOT:-}"
  )"
  [[ "$current" == "$expected" ]] || die "activated controller.env does not use shared physical device root $expected; copy the existing physical_device_id into that root, update PHYSICAL_DEVICE_DATA_ROOT, then rerun this installer"
}

install_controller_files() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this script supports Darwin only"
  sudo mkdir -p "$INSTALL_DIR"
  chmod 700 "$INSTALL_DIR"
  if env_has_control_token; then
    echo "[codem-zone-controller] preserving existing activated controller.env"
    require_shared_store_root
    require_shared_physical_device_root
  else
    cat > "$ENV_FILE" <<'CODEM_CONTROLLER_ENV_20Femevo'
CODEM_RESOURCE_ENV='prod'
ZONE_CONTROL_PLANE_SERVER_URL='https://codem.feishu.cn/goapi/codem'
ZONE_CONTROL_PLANE_TRANSPORT='post'
ZONE_ACTIVATE_URL=''
ZONE_INSTALL_TOKEN='czit_1XY8Pi-Dyr2Lq2mlEUozgg-nKMTLl5_o'
ZONE_CONTROL_PLANE_TOKEN=''
CODEM_SANDBOX_CONTROLLER_TOKEN=''
CODEM_SANDBOX_CONTROL_PLANE_TOKEN=''
ZONE_META_CONTENT_TOKEN=''
TENANT_KEY='7626801208162028765'
PROJECT_KEY='proj_7687448577710230507'
CLUSTER_KEY='sbc_7688217783607233509'
ZONE_KEY='zone_muc75rux2ro5xk'
LOGICAL_SANDBOX_ID='lsbx_muc75rux2ro5xk'
CONTROLLER_ID='ctrl_B80jWmxrv3'
ZONE_INSTALL_TOKEN_EXPIRES_AT='2026-09-25T04:51:41.00172645Z'
ZONE_CONTROL_PLANE_TOKEN_EXPIRES_AT=''
CONTROLLER_NAME='codem-zone-controller-zone_muc75rux2ro5xk'
CONTROLLER_IMAGE='codem-cn-beijing.cr.volces.com/base/codem-zone-controller:ad1e5da6a044b31144b00595f1e1e329'
DISPATCHER_ALLOWED_IMAGES='codem-cn-beijing.cr.volces.com/base/codem-sandbox-base:*'
HEALTH_PORT=''
HEALTH_PORT_RANGE='18080-18199'
CONTAINER_HEALTH_PORT='8080'
RESTART_POLICY='unless-stopped'
CODEM_STORAGE_RETENTION_TTL='168h'
CONTROLLER_DATA_ROOT='/usr/local/var/lib/codem/private-zones/lsbx_muc75rux2ro5xk/controller'
DISPATCHER_STORE_ROOT='/usr/local/var/lib/codem/codem-sandbox'
PHYSICAL_DEVICE_DATA_ROOT='/usr/local/var/lib/codem/physical-device'
WORKER_SERVER_URL=''
WORKER_CONTAINER_NAME_PREFIX='codem-worker-zone_muc75rux2ro5xk-'
SHARED_READONLY_ROOTS=''
DOCKER_SOCKET_PATH=''
CODEM_EXTRA_CA_CERT_PATH=''
CODEM_CONTROLLER_ENV_20Femevo
  fi
  chmod 600 "$ENV_FILE"
  cat > "$CONTROLLER_SCRIPT" <<'CODEM_CONTROLLER_SCRIPT_qaCWDVmY'
#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-start}"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
ENV_FILE="${2:-${CODEM_ZONE_CONTROLLER_ENV_FILE:-${SCRIPT_DIR}/controller.env}}"
CODEM_ROOT='/usr/local/var/lib/codem'

die() { echo "error: $*" >&2; exit 1; }
log() { echo "[codem-zone-controller] $*"; }
step() { log "==> $*"; }

load_env_file() {
  [[ -f "$ENV_FILE" ]] || die "env file not found: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  normalize_resource_environment
}

normalize_resource_environment() {
  CODEM_RESOURCE_ENV="${CODEM_RESOURCE_ENV:-prod}"
  case "$CODEM_RESOURCE_ENV" in
    canary|CANARY|Canary) CODEM_RESOURCE_ENV=prod ;;
  esac
  export CODEM_RESOURCE_ENV
}

normalize_runtime_post_base_url() {
  local server_url="$1"
  server_url="${server_url%%#*}"
  server_url="${server_url%%\?*}"
  local suffix
  for suffix in /ws/zone-control-plane /ws/sandbox /sandbox/sync /agent/sync; do
    if [[ "$server_url" == *"$suffix" ]]; then
      server_url="${server_url%"$suffix"}"
      break
    fi
  done
  server_url="${server_url%/}"
  if [[ "$server_url" == wss://* ]]; then printf 'https://%s' "${server_url#wss://}"; return; fi
  if [[ "$server_url" == ws://* ]]; then printf 'http://%s' "${server_url#ws://}"; return; fi
  printf '%s' "$server_url"
}

derive_http_server_url() {
  normalize_runtime_post_base_url "$1"
}

derive_worker_server_url() {
  normalize_runtime_post_base_url "$1"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

activation_payload() {
  local host_name controller_version
  host_name="$(hostname 2>/dev/null || true)"
  controller_version="${ZONE_CONTROL_PLANE_VERSION:-$CONTROLLER_IMAGE}"
  cat <<JSON
{"tenant_id":"$(json_escape "$TENANT_KEY")","project_key":"$(json_escape "$PROJECT_KEY")","cluster_key":"$(json_escape "$CLUSTER_KEY")","zone_key":"$(json_escape "$ZONE_KEY")","logical_sandbox_id":"$(json_escape "$LOGICAL_SANDBOX_ID")","install_token":"$(json_escape "$ZONE_INSTALL_TOKEN")","controller_id":"$(json_escape "$CONTROLLER_ID")","controller_name":"$(json_escape "$CONTROLLER_NAME")","host":"$(json_escape "$host_name")","version":"$(json_escape "$controller_version")","container_name":"$(json_escape "$CONTROLLER_NAME")"}
JSON
}

json_string_field() {
  local file="$1"
  local key="$2"
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n1
}

json_number_field() {
  local file="$1"
  local key="$2"
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([-0-9][0-9]*\\).*/\\1/p" "$file" | head -n1
}

first_json_string_field() {
  local file="$1"
  shift
  local key value
  for key in "$@"; do
    value="$(json_string_field "$file" "$key")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
}

activation_response_code() {
  local file="$1"
  local code
  code="$(json_number_field "$file" code)"
  if [[ -z "$code" ]]; then
    code="$(json_number_field "$file" StatusCode)"
  fi
  printf '%s' "$code"
}

activation_response_message() {
  first_json_string_field "$1" msg message error_description errorMessage error_msg reason name
}

load_activation_response() {
  local file="$1"
  if grep -q '^ZONE_CONTROL_PLANE_TOKEN=' "$file"; then
    # shellcheck disable=SC1090
    source "$file"
    return
  fi
  local code message
  code="$(activation_response_code "$file")"
  if [[ -n "$code" && "$code" != "0" ]]; then
    message="$(activation_response_message "$file")"
    if [[ -n "$message" ]]; then
      die "activation failed: code=$code message=$message. Regenerate the private zone install script if this token or zone is no longer valid."
    fi
    die "activation failed: code=$code. Regenerate the private zone install script if this token or zone is no longer valid."
  fi
  ZONE_CONTROL_PLANE_TOKEN="$(first_json_string_field "$file" control_plane_token controlPlaneToken ControlPlaneToken controllerToken)"
  ZONE_CONTROL_PLANE_TOKEN_EXPIRES_AT="$(first_json_string_field "$file" control_plane_token_expires_at controlPlaneTokenExpiresAt ControlPlaneTokenExpiresAt controllerTokenExpiresAt)"
}

redact_url() {
  local url="$1"
  printf '%s' "${url%%\?*}"
}

persist_env_value() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$ENV_FILE" ]]; then
    grep -v "^${key}=" "$ENV_FILE" > "$tmp" || true
  fi
  printf "%s='%s'\n" "$key" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")" >> "$tmp"
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
}

activate_controller_token() {
  if [[ -n "${ZONE_CONTROL_PLANE_TOKEN:-}" ]]; then return; fi
  [[ -n "${ZONE_INSTALL_TOKEN:-}" ]] || die "ZONE_INSTALL_TOKEN is required before first start. Regenerate the private zone install script from CodeM, then run this script again."
  command -v curl >/dev/null 2>&1 || die "curl is required to activate the private zone controller. Install curl and rerun this script."
  local activate_url tmp curl_err http_status message code
  local env_headers=()
  activate_url="${ZONE_ACTIVATE_URL:-$(derive_http_server_url "$ZONE_CONTROL_PLANE_SERVER_URL")/sandbox_controller/private_zones/install/activate}"
  tmp="$(mktemp)"
  curl_err="$(mktemp)"
  case "$CODEM_RESOURCE_ENV" in
    prod|local) ;;
    ppe|ppe_*|ppe-*) env_headers=(-H "X-TT-ENV: $CODEM_RESOURCE_ENV" -H 'X-USE-PPE: 1') ;;
    *) env_headers=(-H "X-TT-ENV: $CODEM_RESOURCE_ENV") ;;
  esac
  if ! http_status="$(curl -sS -w '%{http_code}' -X POST "$activate_url" \
    -H 'Content-Type: application/json' \
    -H 'Accept: text/plain, application/json' \
    "${env_headers[@]+"${env_headers[@]}"}" \
    -d "$(activation_payload)" \
    -o "$tmp" 2>"$curl_err")"; then
    message="$(tr '\n' ' ' < "$curl_err")"
    message="${message:0:500}"
    rm -f "$tmp" "$curl_err"
    die "activation request failed: POST $(redact_url "$activate_url") could not reach CodeM (${message:-curl failed}). Check network, DNS, and gateway access, then rerun this script."
  fi
  rm -f "$curl_err"
  if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    code="$(activation_response_code "$tmp")"
    message="$(activation_response_message "$tmp")"
    rm -f "$tmp"
    if [[ -n "$code" && -n "$message" ]]; then
      die "activation request failed: POST $(redact_url "$activate_url") returned HTTP $http_status code=$code message=$message. Regenerate the private zone install script if the install token has expired."
    fi
    if [[ -n "$message" ]]; then
      die "activation request failed: POST $(redact_url "$activate_url") returned HTTP $http_status message=$message. Regenerate the private zone install script if the install token has expired."
    fi
    die "activation request failed: POST $(redact_url "$activate_url") returned HTTP $http_status. Regenerate the private zone install script if the install token has expired."
  fi
  load_activation_response "$tmp"
  rm -f "$tmp"
  [[ -n "${ZONE_CONTROL_PLANE_TOKEN:-}" ]] || die "activation succeeded but response did not include ZONE_CONTROL_PLANE_TOKEN. Regenerate the private zone install script or contact CodeM support with the activation time and zone key."
  ZONE_META_CONTENT_TOKEN="${ZONE_META_CONTENT_TOKEN:-$ZONE_CONTROL_PLANE_TOKEN}"
  CODEM_SANDBOX_CONTROLLER_TOKEN="${CODEM_SANDBOX_CONTROLLER_TOKEN:-$ZONE_CONTROL_PLANE_TOKEN}"
  CODEM_SANDBOX_CONTROL_PLANE_TOKEN="${CODEM_SANDBOX_CONTROL_PLANE_TOKEN:-$ZONE_CONTROL_PLANE_TOKEN}"
  persist_env_value ZONE_CONTROL_PLANE_TOKEN "$ZONE_CONTROL_PLANE_TOKEN"
  persist_env_value CODEM_SANDBOX_CONTROLLER_TOKEN "$CODEM_SANDBOX_CONTROLLER_TOKEN"
  persist_env_value CODEM_SANDBOX_CONTROL_PLANE_TOKEN "$CODEM_SANDBOX_CONTROL_PLANE_TOKEN"
  if [[ -n "${ZONE_CONTROL_PLANE_TOKEN_EXPIRES_AT:-}" ]]; then
    persist_env_value ZONE_CONTROL_PLANE_TOKEN_EXPIRES_AT "$ZONE_CONTROL_PLANE_TOKEN_EXPIRES_AT"
  fi
  persist_env_value ZONE_META_CONTENT_TOKEN "$ZONE_META_CONTENT_TOKEN"
  persist_env_value ZONE_INSTALL_TOKEN ""
}

validate_config() {
  local missing=() key value
  normalize_resource_environment
  for key in CODEM_RESOURCE_ENV ZONE_CONTROL_PLANE_SERVER_URL TENANT_KEY PROJECT_KEY CLUSTER_KEY ZONE_KEY LOGICAL_SANDBOX_ID CONTROLLER_ID CONTROLLER_NAME CONTROLLER_IMAGE CONTROLLER_DATA_ROOT DISPATCHER_STORE_ROOT PHYSICAL_DEVICE_DATA_ROOT; do
    value="${!key:-}"
    if [[ -z "$value" ]]; then
      missing+=("$key")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    die "controller.env is incomplete: missing ${missing[*]}. Regenerate the private zone install script from CodeM, or restore the missing values in $ENV_FILE."
  fi
}

port_is_free() {
  local port="$1"
  (echo >"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1 && return 1
  return 0
}

choose_health_port() {
  if [[ -n "${HEALTH_PORT:-}" ]]; then printf '%s' "$HEALTH_PORT"; return; fi
  local range start end port
  range="${HEALTH_PORT_RANGE:-18080-18199}"
  start="${range%-*}"
  end="${range#*-}"
  if [[ ! "$start" =~ ^[0-9]+$ || ! "$end" =~ ^[0-9]+$ || "$start" -gt "$end" ]]; then
    die "invalid HEALTH_PORT_RANGE: $range"
  fi
  for ((port=start; port<=end; port++)); do
    if port_is_free "$port"; then printf '%s' "$port"; return; fi
  done
  die "no free health port in range: $range. Set HEALTH_PORT in $ENV_FILE or widen HEALTH_PORT_RANGE, then rerun this script."
}

prepare_runtime_defaults() {
  WORKER_SERVER_URL="${WORKER_SERVER_URL:-$(derive_worker_server_url "$ZONE_CONTROL_PLANE_SERVER_URL")}"
  ZONE_CONTROL_PLANE_TRANSPORT="${ZONE_CONTROL_PLANE_TRANSPORT:-post}"
  CONTAINER_HEALTH_PORT="${CONTAINER_HEALTH_PORT:-8080}"
  HEALTH_PORT="$(choose_health_port)"
  prepare_extra_ca_cert
  persist_env_value WORKER_SERVER_URL "$WORKER_SERVER_URL"
  persist_env_value ZONE_CONTROL_PLANE_TRANSPORT "$ZONE_CONTROL_PLANE_TRANSPORT"
  persist_env_value HEALTH_PORT "$HEALTH_PORT"
  persist_env_value CONTAINER_HEALTH_PORT "$CONTAINER_HEALTH_PORT"
}

append_shared_readonly_mounts() {
  local roots="${SHARED_READONLY_ROOTS:-}"
  [[ -n "$roots" ]] || return
  local IFS=',' item host_path container_path
  for item in $roots; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] || continue
    host_path="$item"
    container_path="$item"
    if [[ "$item" == *:* ]]; then
      host_path="${item%%:*}"
      container_path="${item#*:}"
    fi
    [[ -n "$host_path" && -n "$container_path" ]] || die "invalid shared readonly root: $item"
    printf '%s\0' -v "${host_path}:${container_path}:ro"
  done
}

host_user_home() {
  local home_dir="${HOME:-}"
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
    local user_name="${SUDO_USER:-}"
    if [[ -z "$user_name" || "$user_name" == "root" ]]; then
      user_name="$(stat -f %Su /dev/console 2>/dev/null || true)"
    fi
    if [[ -n "$user_name" && "$user_name" != "root" ]]; then
      local detected_home
      detected_home="$(dscl . -read "/Users/${user_name}" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
      if [[ -n "$detected_home" ]]; then
        home_dir="$detected_home"
      fi
    fi
  fi
  printf '%s' "$home_dir"
}

detect_macos_extra_ca_cert() {
  [[ -z "${CODEM_EXTRA_CA_CERT_PATH:-}" ]] || return 0
  [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] || return 0

  local home_dir candidate
  home_dir="$(host_user_home)"
  [[ -n "$home_dir" ]] || return 0

  candidate="${home_dir}/.WhistleAppData/.whistle/certs/root.crt"
  if [[ -f "$candidate" ]]; then
    CODEM_EXTRA_CA_CERT_PATH="$candidate"
    log "auto-detected macOS Whistle CA: $candidate"
  fi
}

prepare_extra_ca_cert() {
  EXTRA_CA_MOUNT_ARG=""
  EXTRA_CA_CONTAINER_PATH=""

  detect_macos_extra_ca_cert
  [[ -n "${CODEM_EXTRA_CA_CERT_PATH:-}" ]] || return 0

  [[ "$CODEM_EXTRA_CA_CERT_PATH" == /* ]] || die "CODEM_EXTRA_CA_CERT_PATH must be absolute: $CODEM_EXTRA_CA_CERT_PATH"
  if [[ -f "$CODEM_EXTRA_CA_CERT_PATH" ]]; then
    EXTRA_CA_CONTAINER_PATH="/etc/codem-extra-certs/codem-extra-ca.crt"
    EXTRA_CA_MOUNT_ARG="${CODEM_EXTRA_CA_CERT_PATH}:${EXTRA_CA_CONTAINER_PATH}:ro"
  elif [[ -d "$CODEM_EXTRA_CA_CERT_PATH" ]]; then
    EXTRA_CA_CONTAINER_PATH="/etc/codem-extra-certs"
    EXTRA_CA_MOUNT_ARG="${CODEM_EXTRA_CA_CERT_PATH}:${EXTRA_CA_CONTAINER_PATH}:ro"
  else
    die "extra CA cert path does not exist: $CODEM_EXTRA_CA_CERT_PATH"
  fi
  persist_env_value CODEM_EXTRA_CA_CERT_PATH "$CODEM_EXTRA_CA_CERT_PATH"
}

append_extra_ca_mount() {
  [[ -n "${EXTRA_CA_MOUNT_ARG:-}" ]] || return 0
  printf '%s\0' \
    -v "$EXTRA_CA_MOUNT_ARG" \
    -e "CODEM_EXTRA_CA_CERT_PATH=${EXTRA_CA_CONTAINER_PATH}" \
    -e "SSL_CERT_DIR=/etc/ssl/certs:/etc/codem-extra-certs"
}

docker_args() {
  printf '%s\0' \
    --name "$CONTROLLER_NAME" \
    --restart "${RESTART_POLICY:-unless-stopped}" \
    --label "codem.component=zone-controller" \
    --label "codem.tenant=$TENANT_KEY" \
    --label "codem.project=$PROJECT_KEY" \
    --label "codem.cluster=$CLUSTER_KEY" \
    --label "codem.zone=$ZONE_KEY" \
    -e "CODEM_RESOURCE_ENV=$CODEM_RESOURCE_ENV" \
    -e "ZONE_CONTROL_PLANE_SERVER_URL=$ZONE_CONTROL_PLANE_SERVER_URL" \
    -e "ZONE_CONTROL_PLANE_TRANSPORT=${ZONE_CONTROL_PLANE_TRANSPORT:-post}" \
    -e "WORKER_SERVER_URL=$WORKER_SERVER_URL" \
    -e "ZONE_CONTROL_PLANE_TOKEN=$ZONE_CONTROL_PLANE_TOKEN" \
    -e "CODEM_SANDBOX_CONTROLLER_TOKEN=${CODEM_SANDBOX_CONTROLLER_TOKEN:-$ZONE_CONTROL_PLANE_TOKEN}" \
    -e "CODEM_SANDBOX_CONTROL_PLANE_TOKEN=${CODEM_SANDBOX_CONTROL_PLANE_TOKEN:-$ZONE_CONTROL_PLANE_TOKEN}" \
    -e "ZONE_META_CONTENT_TOKEN=${ZONE_META_CONTENT_TOKEN:-$ZONE_CONTROL_PLANE_TOKEN}" \
    -e "TENANT_KEY=$TENANT_KEY" \
    -e "PROJECT_KEY=$PROJECT_KEY" \
    -e "CLUSTER_KEY=$CLUSTER_KEY" \
    -e "ZONE_KEY=$ZONE_KEY" \
    -e "LOGICAL_SANDBOX_ID=$LOGICAL_SANDBOX_ID" \
    -e "CONTROLLER_ID=$CONTROLLER_ID" \
    -e "CONTROLLER_NAME=$CONTROLLER_NAME" \
    -e "DISPATCHER_ALLOWED_IMAGES=${DISPATCHER_ALLOWED_IMAGES:-*}" \
    -e "HEALTH_PORT=$HEALTH_PORT" \
    -e "HEALTH_PORT_RANGE=${HEALTH_PORT_RANGE:-18080-18199}" \
    -e "CONTAINER_HEALTH_PORT=$CONTAINER_HEALTH_PORT" \
    -e "DISPATCHER_HEALTH_ADDR=:${CONTAINER_HEALTH_PORT}" \
    -e "CONTROLLER_DATA_ROOT=$CONTROLLER_DATA_ROOT" \
    -e "DISPATCHER_STORE_ROOT=$DISPATCHER_STORE_ROOT" \
    -e "CODEM_STORAGE_RETENTION_TTL=${CODEM_STORAGE_RETENTION_TTL:-168h}" \
    -e "WORKER_CONTAINER_NAME_PREFIX=${WORKER_CONTAINER_NAME_PREFIX:-}" \
    -v "${CONTROLLER_DATA_ROOT}:/var/lib/codem-zone-controller" \
    -v "${DISPATCHER_STORE_ROOT}:${DISPATCHER_STORE_ROOT}" \
    -v "${PHYSICAL_DEVICE_DATA_ROOT}:/var/lib/codem-physical-device" \
    -p "${HEALTH_PORT}:${CONTAINER_HEALTH_PORT}"
  if [[ -n "${DOCKER_SOCKET_PATH:-}" ]]; then
    printf '%s\0' -v "${DOCKER_SOCKET_PATH}:/var/run/docker.sock"
  else
    printf '%s\0' -v "/var/run/docker.sock:/var/run/docker.sock"
  fi
  append_extra_ca_mount
  append_shared_readonly_mounts
}

wait_controller_health() {
  local url="http://127.0.0.1:${HEALTH_PORT}/healthz"
  local attempt
  for attempt in {1..30}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      log "controller health check passed: $url"
      return
    fi
    sleep 1
  done
  docker logs --tail 80 "$CONTROLLER_NAME" >&2 || true
  die "controller health check failed at $url after 30s. Inspect logs with: $0 logs"
}

update_docker_file_sharing_config() {
  local settings="$1"
  local target="$2"
  local tmp backup rc
  [[ -f "$settings" ]] || return 1
  command -v awk >/dev/null 2>&1 || return 1

  tmp="${settings}.tmp.$$"
  backup="${settings}.bak.$(date +%Y%m%d%H%M%S)"
  set +e
  CODEM_DOCKER_SHARE_TARGET="$target" CODEM_DOCKER_SHARE_OUTPUT="$tmp" awk '
    function json_escape(value,    out, i, ch) {
      out = ""
      for (i = 1; i <= length(value); i++) {
        ch = substr(value, i, 1)
        if (ch == "\\") {
          out = out "\\\\"
        } else if (ch == "\"") {
          out = out "\\\""
        } else {
          out = out ch
        }
      }
      return out
    }
    function skip_ws(pos,    ch) {
      while (pos <= text_len) {
        ch = substr(text, pos, 1)
        if (ch != " " && ch != "\t" && ch != "\r" && ch != "\n") {
          break
        }
        pos++
      }
      return pos
    }
    function read_string(pos,    i, ch, escape, value) {
      value = ""
      escape = 0
      for (i = pos + 1; i <= text_len; i++) {
        ch = substr(text, i, 1)
        if (escape) {
          value = value ch
          escape = 0
          continue
        }
        if (ch == "\\") {
          escape = 1
          continue
        }
        if (ch == "\"") {
          parsed_string = value
          parsed_end = i
          return 1
        }
        value = value ch
      }
      return 0
    }
    function scan_array(pos, target,    i, ch, escape, in_string, value, depth) {
      depth = 1
      escape = 0
      in_string = 0
      value = ""
      for (i = pos + 1; i <= text_len; i++) {
        ch = substr(text, i, 1)
        if (in_string) {
          if (escape) {
            value = value ch
            escape = 0
            continue
          }
          if (ch == "\\") {
            escape = 1
            continue
          }
          if (ch == "\"") {
            if (value == target) {
              target_found = 1
            }
            in_string = 0
            value = ""
            continue
          }
          value = value ch
          continue
        }
        if (ch == "\"") {
          in_string = 1
          value = ""
          continue
        }
        if (ch == "[") {
          depth++
          continue
        }
        if (ch == "]") {
          depth--
          if (depth == 0) {
            array_end = i
            return 1
          }
        }
      }
      return 0
    }
    {
      text = text $0 ORS
    }
    END {
      target = ENVIRON["CODEM_DOCKER_SHARE_TARGET"]
      output = ENVIRON["CODEM_DOCKER_SHARE_OUTPUT"]
      text_len = length(text)
      for (i = 1; i <= text_len; i++) {
        if (substr(text, i, 1) != "\"") {
          continue
        }
        if (!read_string(i)) {
          exit 1
        }
        key = parsed_string
        key_end = parsed_end
        i = parsed_end
        pos = skip_ws(key_end + 1)
        if (key != "FilesharingDirectories" || substr(text, pos, 1) != ":") {
          continue
        }
        pos = skip_ws(pos + 1)
        if (substr(text, pos, 1) != "[") {
          exit 1
        }
        array_start = pos
        if (!scan_array(array_start, target)) {
          exit 1
        }
        key_found = 1
        break
      }
      if (!key_found) {
        exit 1
      }
      if (target_found) {
        exit 2
      }
      content = substr(text, array_start + 1, array_end - array_start - 1)
      escaped = json_escape(target)
      if (content ~ /^[ \t\r\n]*$/) {
        next_content = "\"" escaped "\""
      } else {
        next_content = content ",\"" escaped "\""
      }
      next_text = substr(text, 1, array_start) next_content substr(text, array_end)
      printf "%s", next_text > output
    }
  ' "$settings"
  rc=$?
  set -e
  if [[ "$rc" == 2 ]]; then
    rm -f "$tmp"
    return 2
  fi
  if [[ "$rc" != 0 || ! -s "$tmp" ]]; then
    rm -f "$tmp"
    return 1
  fi
  if ! grep -Fq "\"$target\"" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  cp -p "$settings" "$backup" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$settings" || {
    cp "$backup" "$settings" 2>/dev/null || true
    rm -f "$tmp"
    return 1
  }
  DOCKER_FILE_SHARING_BACKUP="$backup"
  return 0
}

change_mac_docker_file_share() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  step "change docker file share config"
  local settings="$(host_user_home)/Library/Group Containers/group.com.docker/settings-store.json"
  local update_status

  local normal_user_name="${SUDO_USER:-}"
  if [[ -z "$normal_user_name" || "$normal_user_name" == "root" ]]; then
    normal_user_name="$(stat -f %Su /dev/console 2>/dev/null || true)"
  fi

  sudo mkdir -p "$CODEM_ROOT" || {
    echo "[codem] warning: failed to create CodeM root: $CODEM_ROOT" >&2
    return 0
  }
  sudo chmod 755 "$CODEM_ROOT" || {
    echo "[codem] warning: failed to chmod CodeM root: $CODEM_ROOT" >&2
    return 0
  }
  # The directory on Mac cannot be root; Docker runs under a regular user account
  sudo chown -R "$normal_user_name":staff "$CODEM_ROOT" "$CONTROLLER_DATA_ROOT" "$DISPATCHER_STORE_ROOT" || {
    echo "[codem] warning: failed to chown Docker shared directories" >&2
    return 0
  }

  [[ -f "$settings" ]] || return 0
  if update_docker_file_sharing_config "$settings" "$CODEM_ROOT"; then
    update_status=0
  else
    update_status=$?
  fi
  if [[ "$update_status" == 2 ]]; then
    return 0
  fi
  if [[ "$update_status" != 0 ]]; then
    echo "[codem] warning: failed to update Docker File Sharing" >&2
    return 0
  fi
  [[ -n "${DOCKER_FILE_SHARING_BACKUP:-}" ]] || return 0
  # sudo docker desktop not work
  if ! sudo -u "$normal_user_name" docker desktop restart; then
    echo "[codem] warning: failed to restart Docker Desktop; restoring previous File Sharing config" >&2
    if [[ -n "${DOCKER_FILE_SHARING_BACKUP:-}" && -f "$DOCKER_FILE_SHARING_BACKUP" ]]; then
      cp "$DOCKER_FILE_SHARING_BACKUP" "$settings" 2>/dev/null || true
      sudo -u "$normal_user_name" docker desktop restart >/dev/null 2>&1 || true
    fi
    return 0
  fi
}

start_controller() {
  step "validating controller.env"
  validate_config
  step "preparing runtime defaults"
  prepare_runtime_defaults
  command -v docker >/dev/null 2>&1 || die "docker is required. Install or start Docker, then rerun this script."
  step "checking Docker availability"
  docker info >/dev/null || die "Docker is unavailable. Install or start Docker and enable the required runtime integration, then rerun this script."
  step "pulling controller image $CONTROLLER_IMAGE"
  docker pull "$CONTROLLER_IMAGE" || die "failed to pull controller image: $CONTROLLER_IMAGE. Check Docker registry access and image name."
  step "activating controller token"
  activate_controller_token
  [[ -n "${ZONE_CONTROL_PLANE_TOKEN:-}" ]] || die "ZONE_CONTROL_PLANE_TOKEN is required after activation. Regenerate the private zone install script and rerun start."
  docker rm -f "$CONTROLLER_NAME" >/dev/null 2>&1 || true
  mkdir -p "$CONTROLLER_DATA_ROOT" "$DISPATCHER_STORE_ROOT" "$PHYSICAL_DEVICE_DATA_ROOT"
  local args=()
  local arg
  while IFS= read -r -d '' arg; do
    args+=("$arg")
  done < <(docker_args)
  change_mac_docker_file_share
  step "starting controller container $CONTROLLER_NAME"
  docker run -d "${args[@]}" "$CONTROLLER_IMAGE" || die "failed to start controller container $CONTROLLER_NAME. Check Docker permissions, ports, and mounts."
  step "waiting for controller health on port $HEALTH_PORT"
  wait_controller_health
}

status_controller() {
  docker ps -a --filter "name=^/${CONTROLLER_NAME}$"
}

logs_controller() {
  docker logs --tail 200 "$CONTROLLER_NAME"
}

stop_controller() {
  docker stop "$CONTROLLER_NAME"
}

uninstall_controller() {
  docker rm -f "$CONTROLLER_NAME" >/dev/null 2>&1 || true
}

load_env_file
case "$ACTION" in
  start|restart) start_controller ;;
  status) status_controller ;;
  logs) logs_controller ;;
  stop) stop_controller ;;
  uninstall) uninstall_controller ;;
  *) die "unsupported action: $ACTION" ;;
esac
CODEM_CONTROLLER_SCRIPT_qaCWDVmY
  chmod 700 "$CONTROLLER_SCRIPT"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  sudo mkdir -p "$CONTROLLER_DATA_ROOT" "$DISPATCHER_STORE_ROOT" "$PHYSICAL_DEVICE_DATA_ROOT"
  sudo chown -R "$(id -un)":staff "$INSTALL_DIR" "$CONTROLLER_DATA_ROOT" "$DISPATCHER_STORE_ROOT" "$PHYSICAL_DEVICE_DATA_ROOT"
}

install_controller_files

case "$ACTION" in
  start|restart|status|logs|stop|uninstall)
    exec "$CONTROLLER_SCRIPT" "$ACTION" "$ENV_FILE"
    ;;
  *) die "unsupported action: $ACTION" ;;
esac
