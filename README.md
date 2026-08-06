# Docker VPN Proxy
### Forward VPN traffic through an ultra-lightweight Docker container

**NOTE**: This is provided for educational purposes only. Please ensure that this is allowed
by your IT organization before using.

This image creates a Docker container that:

* Connects to your personal or corporate VPN through your or your company's VPN server, and
* Creates a HTTP/HTTPS/SOCK proxy that browsers on your host can use to forward traffic through.

Inspired by [wazum/openconnect-proxy](https://github.com/wazum/openconnect-proxy) and
[matinrco/openconnect-proxy](https://github.com/matinrco/openconnect-proxy).


<!-- vim-markdown-toc GFM -->

* [Why?](#why)
* [Compatible with](#compatible-with)
    * [via OpenConnect](#via-openconnect)
    * [via OpenVPN](#via-openvpn)
    * [via other means](#via-other-means)
* [Not Compatible With](#not-compatible-with)
* [How do I use?](#how-do-i-use)
    * [Configuring docker-proxy](#configuring-docker-proxy)
    * [openconnect](#openconnect)
    * [openvpn](#openvpn)
    * [Netbird](#netbird)
    * [Starting and stopping Docker Proxy](#starting-and-stopping-docker-proxy)
* [Alternate Configurations](#alternate-configurations)
    * [Want to change the HTTP and SOCKS5 proxy ports?](#want-to-change-the-http-and-socks5-proxy-ports)
    * [Need to change the path to the Docker UNIX socket?](#need-to-change-the-path-to-the-docker-unix-socket)
    * [Does your VPN require a client certificate?](#does-your-vpn-require-a-client-certificate)
    * [Does your VPN have multiple gateways?](#does-your-vpn-have-multiple-gateways)
    * [Does your GlobalProtect VPN require Single Sign On authentication?](#does-your-globalprotect-vpn-require-single-sign-on-authentication)
* [Cool Use Cases](#cool-use-cases)
    * [Dedicated browser for separating normal web browsing from "protected" web browsing](#dedicated-browser-for-separating-normal-web-browsing-from-protected-web-browsing)
    * [Execute shell requests through the proxy](#execute-shell-requests-through-the-proxy)
        * [Through proxychains (recommended)](#through-proxychains-recommended)
        * [Through simple environment variables](#through-simple-environment-variables)
        * [Running multiple VPNs at once](#running-multiple-vpns-at-once)
* [Troubleshooting](#troubleshooting)
    * [My connection is really slow. How can I fix it?](#my-connection-is-really-slow-how-can-i-fix-it)
    * [I need to use a csd-wrapper script to connect to my VPN. How can I do that?](#i-need-to-use-a-csd-wrapper-script-to-connect-to-my-vpn-how-can-i-do-that)
    * [I'm running Docker Proxy with a M1 MacBook, but want to use the x86 version. How?](#im-running-docker-proxy-with-a-m1-macbook-but-want-to-use-the-x86-version-how)
    * [I get this weird `512 Custom Error` after logging in.](#i-get-this-weird-512-custom-error-after-logging-in)
    * [I'd like to use `podman`; how can I do that?](#id-like-to-use-podman-how-can-i-do-that)

<!-- vim-markdown-toc -->

## Why?

Use this if you want to use VPN but don't want it taking over all traffic on your machine.

## Compatible with

### via OpenConnect

- Cisco Anyconnect (if configured),
- GlobalProtect
- Juniper VPNs

### via OpenVPN

- Private Internet Access
- NordVPN
- Other major VPN providers

### via other means

- Netbird

## Not Compatible With

- Citrix Netscaler (no open-source tool available for it)

## How do I use?

### Configuring docker-proxy

First, create an `.env` file containing one of the configuration snippets below.

> 📝 An up-to-date example is provided at `.env.example`. _Don't use quotes around the values!_

### openconnect

```
	OPENCONNECT_URL=<Gateway URL>
	OPENCONNECT_USER=<Username>
	OPENCONNECT_PASSWORD=<Password>
	OPENCONNECT_OPTIONS=--authgroup <VPN Group> \
		--servercert <VPN Server Certificate> --protocol=<Protocol> \
		--reconnect-timeout 86400
```

Optionally set a multi factor authentication code:

	OPENCONNECT_MFA_CODE=<Multi factor authentication code>

See the [openconnect documentation](https://www.infradead.org/openconnect/manual.html) for available options. 

### openvpn

```
OPENVPN_CONFIG_FILE=/path/to/config/file
OPENVPN_USERNAME=admin
OPENVPN_PASSWORD=supersecret
```

You can specify additional `--up` or `--down` scripts by setting
`OPENVPN_UP_SCRIPTS` and/or `OPENVPN_DOWN_SCRIPTS` to a comma-separated
list of scripts on your machine and then adding the following to your config
defined by `OPENVPN_CONFIG_FILE`:

```
up /additional_up_scripts
down /additional_down_scripts
```

If your OpenVPN server advertises a nameserver, add this to your config:

```
up /etc/openvpn/update-systemd-resolve.sh
up /etc/openvpn/update-systemd-network.sh
```

### Netbird

```
NETBIRD_URL=https://your-management-url
```

> 📝 If your env file has `OPENVPN_CONFIG_FILE` set, add `DISABLE_OPENVPN=true`
> to prevent Docker Proxy from trying OpenVPN first.


### Starting and stopping Docker Proxy

Next, start the VPN: `./start_vpn.sh`. You will not see any output if successful.

**NOTE**: If your `.env` file is not in your current working directory, use this instead:
`ENV_FILE=/path/to/env ./start_vpn.sh`

Finally, configure your browser to use the proxy by setting its HTTP proxy to `localhost:8118`
and SOCKS proxy to `localhost:8889`.

To stop the VPN, simply run: `./stop_vpn.sh`.

**NOTE**: If your `.env` file is not in your current working directory, use this instead:
`ENV_FILE=/path/to/env ./stop_vpn.sh`

## Alternate Configurations

### Want to change the HTTP and SOCKS5 proxy ports?

Add this to your `.env`:

```sh
HTTP_PROXY_PORT=1234 # change '1234' to your port
SOCKS5_PROXY_PORT=1234 # change '1234' to your port
```

### Need to change the path to the Docker UNIX socket?

Prefix `./{start,stop}_vpn.sh` with `VPN_DOCKER_SOCK=[PATH]`.

### Does your VPN require a client certificate?

If so and you are using openconnect, add this to your `ENV_FILE`:

```sh
OPENCONNECT_CERT_PATH=/path/to/cert
OPENCONNECT_CERT_KEY=/path/to/key
```

If you are using OpenVPN, embed the certificate in `<ca>`, `<cert>`, and `<key>`
statements as needed.

### Does your VPN have multiple gateways?

If so, choose the VPN server corresponding to the gateway that you would like to connect to.
For more info on why you need to do this,
[visit this GitHub issue](https://github.com/dlenski/openconnect/issues/128).

> ✅ If you need to run command-line applications that do not support SOCKS5 or
> HTTP proxies, use `docker cp` to copy them into `/mnt/extras`, then run the
> command with `docker exec`.

### Does your GlobalProtect VPN require Single Sign On authentication?

Some GlobalProtect VPNs require you to log in via a web browser to finish
authenticating.

If that's the case for your VPN, do the following:

1. Download a VNC client, like TigerVNC or RealVNC.
2. Add the following to your `.env` file:

   ```sh
   GP_ENABLE_OIDC_LOGIN=true
   VNC_PASSWORD=enter-password-here
   ```

   If your VPN gateway is using an untrusted root CA, add this as well:

   ```sh
   GP_ENABLE_INSECURE_OIDC_LOGIN=true
   ```

3. Afterwards, run `start_vpn.sh` like normal. When it finishes, open your VNC
   client and connect to `localhost:59000`.

   You should be greeted with a small browser window that you can use to
   complete the authentication process. The VPN connection should be established
   once this completes.

> ⚠️  If you have `$OPENCONNECT_OPTIONS` defined in your `.env`, do not configure
> the following flags:
>
> - `--username, -u`
> - `--portal`
> - `--gateway`

## Cool Use Cases

### Dedicated browser for separating normal web browsing from "protected" web browsing

[Create a separate Firefox profile](https://developer.mozilla.org/en-US/docs/Mozilla/Firefox/Multiple_profiles).
Configure its HTTP proxy to `localhost:8118`, its SOCKS5 proxy to `localhost:8443` and enable
"Proxy DNS request through SOCKS". Boom! You now have a dedicated web browser that goes through
the proxy.

### Execute shell requests through the proxy

#### Through proxychains (recommended)

[`proxychains`](https://github.com/haad/proxychains) is a tool that tunnels all network traffic
from any `libc`-compiled application through SOCKS or HTTP proxies. Unlike the `HTTP_PROXY`
variables, it also supports resolving DNS records through the proxy.

Installing it is easy:

```sh
git clone https://github.com/haad/proxychains &&
  cd proxychains &&
  ./configure && make && make install
```

Using it is easy too:

```sh
PROXYCHAINS_SOCKS5=8889 proxychains4 curl foo.com
```

#### Through simple environment variables

If you need to access a resource through the proxy, simply export these environment variables:

```sh
export HTTP_PROXY=localhost:8118
export HTTPS_PROXY=localhost:8118
export SOCKS_PROXY=localhost:8889
```

or you can put them before your command to use them for one-off processes:

```sh
HTTP_PROXY=localhost:8118 HTTPS_PROXY=localhost:8118 SOCKS_PROXY=localhost:8889 curl [options]
```

#### Running multiple VPNs at once

Connecting to a VPN usually means forwarding all of your network traffic to a
single VPN provider. This gets awkward when you need to work with multiple
VPNs...unless you're using Docker Proxy.

Create `.env` files for every VPN service you need to connect to:

```sh
cat >site-1.env <<-EOF
export HTTP_PROXY_PORT=48118
export SOCKS5_PROXY_PORT=48889
export NETBIRD_URL=https://netbird.site1.company:12345
export DISABLE_OPENVPN=true
EOF

cat >site-2.env <<-EOF
export OPENVPN_CONFIG_FILE=$HOME/site-2.ovpn.config
export HTTP_PROXY_PORT=58118
export SOCKS5_PROXY_PORT=58889
EOF

cat >site-3.env <<-EOF
export OPENCONNECT_USER=username
export OPENCONNECT_PASSWORD=supersecret
export OPENCONNECT_URL=https://vpn.site3.company
export HTTP_PROXY_PORT=68118
export SOCKS5_PROXY_PORT=68889
```

Then start Docker Proxy for each of them:

```sh
for i in $(seq 1 3); do ENV_FILE="site-${i}.env" ./start-vpn.sh; done
```

Now you can create multiple Firefox/Chrome profiles or use a proxy-switching
extension like FoxyProxy to switch between each proxy as needed to access each
VPN without having any of them take over all of your network traffic:

```sh
curl -x socks5h://localhost:48889 example.site1.company # resolves!
curl -x socks5h://localhost:58889 example.site2.company # resolves!
curl -x socks5h://localhost:68889 example.site3.company # resolves!
```

## Troubleshooting

### My connection is really slow. How can I fix it?

Most VPN slowness can be resolved by restarting the VPN container. Run this to do that:
`./restart_vpn.sh`.

> **NOTE**: If your `.env` file is not in your current working directory, use this instead:
>
> ```sh
> ENV_FILE=/path/to/env ./restart_vpn.sh
> ```

### I need to use a csd-wrapper script to connect to my VPN. How can I do that?

This Docker image downloads the Openconnect "trojan" scripts into the `/trojans` directory.
If you need to use one (like `hipreport.sh` for GlobalProtect VPNs), add
`--csd-wrapper=/trojans/hipreport.sh` to the `OPENCONNECT_OPTIONS` environment variable.

### I'm running Docker Proxy with a M1 MacBook, but want to use the x86 version. How?

Run `docker-proxy` like this:

```sh
PLATFORM=amd64 ./start_vpn.sh
```

Remove any `docker_vpn` images before doing this.

### I get this weird `512 Custom Error` after logging in.

Check your username and password. If you're connecting to a GlobalProtect
VPN that is SSO enabled, make sure that you don't have the arguments
outlined in the warning above in your `$OPENCONNECT_OPTIONS`.

### I'd like to use `podman`; how can I do that?

Set `CONTAINER_BIN` to `podman` before running `start_vpn.sh` or `start_vpn.sh`.
However, there are issues with starting VPN devices in Podman containers that
might prevent this from working.

See [this Ask Ubuntu
thread](https://askubuntu.com/questions/1546511/ioctl-tunsetiff-fails-with-eperm-inside-a-podman-container-in-ubuntu-noble)
for more details.
