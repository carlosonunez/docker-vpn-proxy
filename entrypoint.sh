#!/bin/bash
/usr/local/bin/microsocks -i 0.0.0.0 -p 8889 & 
cat >/etc/privoxy/config <<-PRIVOXY_CONFIG
listen-address          0.0.0.0:8118
forward-socks5          /             127.0.0.1:8889    .
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

start_vnc_server() {
  xhost +localhost
  Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
  x11vnc -storepasswd "$1" ~/.vnc/passwd
  x11vnc -forever -usepw -create -display :99 -rfbport 59000 &
}
if test "$(cat /etc/openvpn/openvpn.config)" != "no openvpn config present"
then
  until (run_openvpn); do
    echo "openvpn exited; restarting in 60 seconds..." >&2
    sleep 60
  done
else
  if _oidc_login_required
  then
    if test -z "$VNC_PASSWORD"
    then
      >&2 echo "ERROR: VNC_PASSWORD is required to use OIDC-enabled VPN endpoints."
      exit 1
    fi
    start_vnc_server "$VNC_PASSWORD"
  fi
  until (run_openconnect); do
    echo "openconnect exited. Restarting process in 60 seconds…" >&2
    sleep 60
  done
fi

