#!/usr/bin/env bash
CREATE_DOCKER_VOLUME="${CREATE_DOCKER_VOLUME:-true}"
DELETE_DOCKER_VOLUME="${DELETE_DOCKER_VOLUME:-false}"
CONTAINER_BIN="${CONTAINER_BIN:-docker}"
test -n "$VERBOSE" && set -x
if test -n "$VPN_DOCKER_SOCK"
then
  export DOCKER_HOST="unix://$VPN_DOCKER_SOCK"
fi
_create_scripts() {
  script_file="$1"
  vpn_scripts_csv="$2"
  echo '#!/usr/bin/env bash' > "$script_file"
  if ! test -z "$vpn_scripts_csv"
  then
    while read -r file
    do
      grep -Ev '^#!' "$file" >> "$script_file"
    done < <(tr ',' '\n' < <(echo "$vpn_scripts_csv"))
  else
    echo "true" > "$script_file"
  fi
  chmod +x "$script_file"
}

_vpn_container_image_name() {
  local image_name base_image_name
  base_image_name="local/${CONTAINER_BIN}_vpn"
  image_name="$VPN_DOCKER_IMAGE_NAME"
  test -n "$ENV_FILE" && image_name="${base_image_name}_$(base64 -w 0 <<< "$ENV_FILE" | head -c 24 | tr '[:upper:]' '[:lower:]')"
  test -z "$image_name" && image_name="$base_image_name"
  echo "$image_name"
}

_vpn_container_name() {
  basename "$(_vpn_container_image_name)"
}

env_file_present() {
  test -f "$ENV_FILE"
}

env_file_hash() {
  echo "$ENV_FILE" | md5sum | cut -f1 -d '-' | head -c 8
}

openvpn_config_path() {
  path="$HOME/.config/docker-proxy"
  test -d "$path" || mkdir -p "$path"
  echo "$path"
}

openvpn_config_file() {
  echo "$(openvpn_config_path)/openvpn-config.$(env_file_hash)"
}

openvpn_login_file() {
  echo "$(openvpn_config_path)/openvpn-login.$(env_file_hash)"
}

openvpn_up_file() {
  echo "$(openvpn_config_path)/openvpn-up.$(env_file_hash)"
}

openvpn_down_file() {
  echo "$(openvpn_config_path)/openvpn-down.$(env_file_hash)"
}

create_openvpn_config_file_if_env_var_present() {
  if ! test -z "$OPENVPN_CONFIG_FILE"
  then
    cat "$OPENVPN_CONFIG_FILE" > "$(openvpn_config_file)"
  else
    echo "no openvpn config present" > "$(openvpn_config_file)"
  fi
}

create_openvpn_up_scripts() {
  _create_scripts "$(openvpn_up_file)" "$OPENVPN_UP_SCRIPTS"
}

create_openvpn_down_scripts() {
  _create_scripts "$(openvpn_down_file)" "$OPENVPN_DOWN_SCRIPTS"
}

create_openvpn_login_file() {
  printf "%s\n%s" "${OPENVPN_USERNAME:-none}" "${OPENVPN_PASSWORD:-none}" > "$(openvpn_login_file)"
}

delete_openvpn_login_and_config_file_if_present() {
  rm -f "$(openvpn_config_file)"
  rm -f "$(openvpn_login_file)"
}

delete_openvpn_scripts() {
  rm -f "$(openvpn_up_file)"
  rm -f "$(openvpn_down_file)"
}

build_container_volume() {
  if grep -Eiq '^true$' <<< "$CREATE_DOCKER_VOLUME"
  then
    vol_name="$(printf "%s-volume" "$1")"
    if "$CONTAINER_BIN" volume ls | grep -q "$vol_name"
    then
      printf "%s" "$vol_name"
      return 0
    fi
    result=$("$CONTAINER_BIN" volume create "$vol_name" 2>&1)
    if test "$?" -ne 0
    then
      >&2 echo "ERROR: Failed to create volume '$vol_name': $result"
      return 1
    fi
    printf "%s" "$vol_name"
  fi
}

delete_container_volume_if_requested() {
  grep -Eiq '^true$' <<< "$DELETE_DOCKER_VOLUME" || return 0
  "$CONTAINER_BIN" volume rm "${1}-volume" || true
}

connect_to_vnc_server_if_oidc_login_required() {
  if grep -Eq '^GP_ENABLE_OIDC_LOGIN=' "$ENV_FILE"
  then
    >&2 echo "Attempting to connect to the container's built in VNC server in 3 seconds. \
(Connect to localhost:59000 if this does not work)"
    sleep 3
    open "vnc://localhost:59000"
  fi
}

ENV_FILE="${ENV_FILE:-$(dirname $0)/.env}"
if env_file_present
then
  export $(cat "$ENV_FILE" | grep -v "_OPTIONS" | xargs)
fi
REBUILD_IMAGE="${REBUILD_IMAGE:-false}"
HTTP_PROXY_PORT="${HTTP_PROXY_PORT:-8118}"
SOCKS_PROXY_PORT="${SOCKS_PROXY_PORT:-8889}"

resolve_container_platform_or_fail() {
  _resolve_using_cpu_arch() {
    case "$(uname -m)" in
      x86_64)
        echo "linux/amd64"
        return 0
        ;;
      arm|arm64)
        echo "linux/arm64"
        return 0
        ;;
      *)
        echo "ERROR: Unsupported platform: $(uname -m)"
        exit 1
        ;;
    esac
  }

  _resolve_using_environment_variable() {
    grep -iq 'amd64' <<< "$PLATFORM" && { echo "linux/amd64" && return 0; }
    grep -iq 'arm' <<< "$PLATFORM" && { echo "linux/arm64" && return 0; }
    >&2 echo "ERROR: Unsupported platform: $PLATFORM" && exit 1
  }

  if test -z "$PLATFORM"
  then _resolve_using_cpu_arch
  else _resolve_using_environment_variable
  fi
}

build_container_image() {
  platform="$(resolve_container_platform_or_fail)"
  if ! "$CONTAINER_BIN" images | grep -q "$(_vpn_container_image_name)" || test "$REBUILD_IMAGE" != "false"
  then
    "$CONTAINER_BIN" build --platform "$platform" \
      -t "$(_vpn_container_image_name)" \
      -f $(dirname $0)/Dockerfile $(dirname $0)
  fi
}

start_vpn() {
  if ! env_file_present
  then
    >&2 echo "ERROR: Env file missing at $ENV_FILE (see README.md to learn how to create one)."
    exit 1
  fi
  cert_path=$(cat $ENV_FILE | grep OPENCONNECT_CERT_PATH | cut -f2 -d =)
  key_path=$(cat $ENV_FILE | grep OPENCONNECT_KEY_PATH | cut -f2 -d =)
  create_openvpn_config_file_if_env_var_present
  create_openvpn_login_file
  create_openvpn_up_scripts
  create_openvpn_down_scripts

  build_container_image || return 1
  vol_name=$(build_container_volume "$(_vpn_container_name)") || return 1
  cookie_vol=$(build_container_volume "$(_vpn_container_name)-cookies") || return 1
  if "$CONTAINER_BIN" ps -a | grep -q "$(_vpn_container_name)"
  then
    >&2 echo "ERROR: VPN container '$(_vpn_container_name)' is either running or stopped recently; run 'stop_vpn' and try again."
    return 1
  fi
  if test -z "$cert_path" || test -z "$key_path"
  then
    "$CONTAINER_BIN" run --detach \
      --name "$(_vpn_container_name)" \
      --env-file "$ENV_FILE" \
      -e VERBOSE="$VERBOSE" \
      -v "$(openvpn_config_file):/etc/openvpn/openvpn.config" \
      -v "$(openvpn_login_file):/login_info" \
      -v "$(openvpn_up_file):/additional_up_scripts.sh" \
      -v "$(openvpn_down_file):/additional_down_scripts.sh" \
      -v "${vol_name}:/mnt/extras" \
      -v "${cookie_vol}:/cookies" \
      --privileged \
      --net=host \
      "$(_vpn_container_image_name)" >/dev/null
    connect_to_vnc_server_if_oidc_login_required
  else
    "$CONTAINER_BIN" run --detach \
      --name "$(_vpn_container_name)" \
      --env-file "$ENV_FILE" \
      -e VERBOSE="$VERBOSE" \
      -v $cert_path:/certificate \
      -v $key_path:/key \
      -v "$(openvpn_config_file):/etc/openvpn/openvpn.config" \
      -v "$(openvpn_login_file):/login_info" \
      -v "$(openvpn_up_file):/additional_up_scripts.sh" \
      -v "$(openvpn_down_file):/additional_down_scripts.sh" \
      -v "${vol_name}:/mnt/extras" \
      -v "${cookie_vol}:/cookies" \
      --privileged \
      --net=host \
      "$(_vpn_container_image_name)" >/dev/null
    connect_to_vnc_server_if_oidc_login_required
  fi
}

stop_vpn() {
  if ! env_file_present
  then
    >&2 echo "ERROR: Please create a .env file (see README.md for instructions)."
    exit 1
  fi

  >/dev/null "$CONTAINER_BIN" rm -f "$(_vpn_container_name)"  || true
  delete_openvpn_login_and_config_file_if_present
  delete_openvpn_scripts
  delete_container_volume_if_requested "$(_vpn_container_name)"
}
