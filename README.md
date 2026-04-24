# Proxmox Helper Local

Local Community Scripts style web UI for browsing, reading, and deploying Proxmox Helper Scripts to one or more Proxmox hosts over SSH.

This project is meant to feel like a local companion to the official Community Scripts site, while giving you your own search, host settings, SSH key generation, deploy terminal, and multi-host support.

## Highlights

- Local script library with official-style categories
- Read/detail view similar to the official site
- Search across the full script catalog
- Deploy over SSH with normal mode or persistent reconnect mode
- Per-host SSH auth settings
- SSH key generation from the UI
- Automatic Ubuntu install with Node.js + PM2
- Automatic Proxmox host flow that can create a dedicated Ubuntu LXC for the app

## Repository Layout

```text
server.js
public/index.html
package.json
setup.sh
LICENSE
README.md
```

## Install Overview

`setup.sh` supports two main paths:

### 1. Host Mode

Installs directly on the current Ubuntu or Debian system.

It will:

1. Install base packages
2. Install Node.js
3. Install PM2
4. Clone or update this repo
5. Run `npm install`
6. Start the app with PM2
7. Save PM2 and hook it into systemd when available

### 2. Proxmox LXC Mode

When you run the installer on a Proxmox host, it can create a dedicated Ubuntu LXC and install the app there instead of on the host itself.

It will:

1. Detect that it is running on Proxmox
2. Auto-detect the Proxmox host IP if you did not pass `--host`
3. Create a dedicated Ubuntu LXC
4. Start the container
5. Download and run `setup.sh` inside the new container
6. Install Node.js and PM2 inside that LXC
7. Start the app there

That keeps the app off the Proxmox host itself.

## Important GitHub URL Note

For installation, use the raw file URL, not the GitHub page URL.

Your browser URL:

```text
https://github.com/Gam3ReaTr0/Proxmox-helper-script-locally/blob/main/setup.sh
```

Install URL:

```text
https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh
```

## Quick Start

### Run on a Proxmox host and let it create its own LXC

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s --
```

That will:

- detect the Proxmox host IP automatically
- create the LXC automatically
- install the app inside the LXC

### Run on a normal Ubuntu or Debian machine

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- --mode host
```

## LXC Networking

By default, the new LXC uses DHCP:

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- --mode lxc --lxc-ip dhcp
```

If you want people to choose their own IP for the new LXC, pass a static IP and gateway:

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --mode lxc \
  --lxc-ip 192.168.8.50/24 \
  --lxc-gateway 192.168.8.1
```

That makes the created LXC come up with that exact address.

## Common Commands

### Proxmox host, automatic LXC creation

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --mode lxc
```

### Proxmox host, static IP for the created LXC

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --mode lxc \
  --lxc-id 301 \
  --lxc-name proxmox-helper-local \
  --lxc-memory 2048 \
  --lxc-cores 2 \
  --lxc-disk 8 \
  --lxc-ip 192.168.8.50/24 \
  --lxc-gateway 192.168.8.1
```

### Force direct install on Ubuntu instead of creating an LXC

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --mode host \
  --host 192.168.8.12
```

### Override the default Proxmox host IP used by the app

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --mode lxc \
  --host 192.168.8.12
```

If you omit `--host` on a Proxmox host, the installer now tries to detect it automatically.

## setup.sh Options

```text
--mode <auto|host|lxc>
--install-on-host
--lxc
--repo <git-url>
--branch <name>
--dir <path>
--host <address>
--port <port>
--node-major <version>
--lxc-id <id>
--lxc-name <name>
--lxc-storage <storage>
--lxc-template-storage <name>
--lxc-template <template>
--lxc-memory <mb>
--lxc-cores <count>
--lxc-disk <gb>
--bridge <name>
--lxc-ip <dhcp|ip/cidr>
--lxc-gateway <ip>
```

## What The Installer Configures

The backend reads:

- `PORT`
- `PROXMOX_HOST_IP`

The installer writes those automatically into:

```text
.runtime.env
ecosystem.config.cjs
```

The app stores local runtime data, SSH keys, and saved host settings in:

```text
data/
```

That directory is ignored by git so you do not accidentally upload private keys or local settings.

## PM2 Runtime

Useful commands after install:

```bash
pm2 status
pm2 logs proxmox-helper-local
pm2 restart proxmox-helper-local
pm2 save
```

If the app was installed inside an LXC, useful Proxmox commands are:

```bash
pct status 301
pct enter 301
pct stop 301
pct start 301
```

## Manual Local Run

If you just want to run it manually:

```bash
npm install
PORT=3000 PROXMOX_HOST_IP=192.168.8.12 npm start
```

Then open:

```text
http://YOUR_SERVER_IP:3000
```

## Uploading Through GitHub In The Browser

If you upload through the GitHub website instead of git on the server, make sure these files are included:

- `server.js`
- `public/index.html`
- `package.json`
- `setup.sh`
- `README.md`
- `LICENSE`
- `.gitignore`

That workflow is fine. The install command runs `setup.sh` with `bash`, so it does not depend on GitHub preserving executable permissions.

## Notes

- On Proxmox hosts, the default `auto` mode creates a dedicated Ubuntu LXC
- On normal Ubuntu/Debian machines, the default `auto` mode installs directly on the current system
- If you omit `--host` on Proxmox, the installer tries to auto-detect the Proxmox host IP
- If you omit `--lxc-ip`, the created LXC uses DHCP
- If you want a fixed IP for the created LXC, use `--lxc-ip` and `--lxc-gateway`
