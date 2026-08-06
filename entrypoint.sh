#!/bin/bash
test -n "$VERBOSE" && set -x
proxy_port="${HTTP_PROXY_PORT:-8118}"
socks_port="${SOCKS5_PROXY_PORT:-8889}"
>&2 echo "Starting docker-proxy VPN helper (http port: $proxy_port, socks5 port: $socks_port)"
/usr/local/bin/microsocks -i 0.0.0.0 -p "$socks_port" & 
cat >/etc/privoxy/config <<-PRIVOXY_CONFIG
listen-address          0.0.0.0:$proxy_port
forward-socks5          /             127.0.0.1:$socks_port    .
PRIVOXY_CONFIG
privoxy /etc/privoxy/config &

_oidc_login_required() {
  test -n "$GP_ENABLE_OIDC_LOGIN"
}

_insecure_oidc_login_enabled() {
  test "$GP_ENABLE_INSECURE_OIDC_LOGIN" == 'true'
}

run_openconnect () {
  # Start openconnect
  options="$OPENCONNECT_OPTIONS"
  if test -f /certificate && test -f /key
  then
    options="$options -c /certificate -k /key"
  fi
  if _oidc_login_required
  then
    command=(gp-saml-gui --gateway -vvv --clientos=Windows -C /cookies/.cookie-jar -S)
    _insecure_oidc_login_enabled && command+=(--allow-insecure-crypto --no-verify)
    command+=("$OPENCONNECT_URL" -- $options)
    DISPLAY=":99" "${command[@]}"
  elif [[ -z "${OPENCONNECT_PASSWORD}" ]]; then
  # Ask for password
    openconnect -u $OPENCONNECT_USER $options $OPENCONNECT_URL
  elif [[ ! -z "${OPENCONNECT_PASSWORD}" ]] && [[ ! -z "${OPENCONNECT_MFA_CODE}" ]]; then
  # Multi factor authentication (MFA)
    (echo $OPENCONNECT_PASSWORD; echo $OPENCONNECT_MFA_CODE) | openconnect -u $OPENCONNECT_USER $options --passwd-on-stdin $OPENCONNECT_URL
  elif [[ ! -z "${OPENCONNECT_PASSWORD}" ]]; then
  # Standard authentication
    echo $OPENCONNECT_PASSWORD | openconnect -u $OPENCONNECT_USER $options --passwd-on-stdin $OPENCONNECT_URL
  fi
}

run_openvpn() {
  openvpn --script-security 2 --config /etc/openvpn/openvpn.config --auth-user-pass /login_info \
    --up /etc/openvpn/update-resolv-conf.sh --down /etc/openvpn/update-resolv-conf.sh --down-pre
}

run_netbird() {
  netbird service run &
  left=30
  while test "$left" -ge 0
  do
    >&2 echo "INFO: Waiting 30 seconds for Netbird service to start ($left seconds left)..."
    netbird status --check live 2>/dev/null && break
    if test "$left" -eq 0
    then
      echo "ERROR: netbird failed to start"
      return 1
    fi
    left=$((left-1))
    sleep 1
  done
  netbird status
  if ! netbird up --management-url "$NETBIRD_URL" --log-file=console,/var/log/netbird/client.log
  then
    echo "ERROR: netbird failed to start"
    return 1
  fi
  tail -f /var/log/netbird/client.log
}

start_vnc_server() {
  xhost +localhost
  Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
  x11vnc -storepasswd "$1" ~/.vnc/passwd
  x11vnc -forever -usepw -create -display :99 -rfbport 59000 &
}
if test -z "$DISABLE_OPENVPN" && test "$(cat /etc/openvpn/openvpn.config)" != "no openvpn config present"
then
  echo "Starting OpenVPN..."
  until (run_openvpn); do
    echo "openvpn exited; restarting in 60 seconds..." >&2
    sleep 60
  done
elif test -z "$DISABLE_NETBIRD" && test -n "$NETBIRD_URL"
then
  echo "Starting Netbird..."
  until (run_netbird); do
    echo "netbird exited; restarting in 60 seconds..." >&2
    sleep 60
  done
elif test -z "$DISABLE_OPENCONNECT" && test -n "$OPENCONNECT_URL"
then
  if _oidc_login_required
  then
    if test -z "$VNC_PASSWORD"
    then
      >&2 echo "ERROR: VNC_PASSWORD is required to use OIDC-enabled VPN endpoints."
      exit 1
    fi
    start_vnc_server "$VNC_PASSWORD"
  fi
  echo "Starting OpenConnect..."
  until (run_openconnect); do
    echo "openconnect exited. Restarting process in 60 seconds…" >&2
    sleep 60
  done
else
  echo "All VPN types disabled; stopping"
  exit 0
fi

