# Proxmox Helper Local

Local Community Scripts style web UI for browsing, reading, and deploying Proxmox Helper Scripts to one or more Proxmox hosts over SSH.

This project is meant to feel like a local deployment companion for the official Community Scripts site, while giving you your own searchable script library, host settings, SSH key generation, and deploy terminal.

## What It Does

- Local script library UI with category browsing
- Detail/read views similar to the official site
- Search across all scripts
- Deploy terminal with normal SSH or persistent reconnect mode
- Per-host SSH settings
- Generated SSH key support
- Ubuntu installer with Node.js + PM2
- Proxmox host installer that can create a dedicated Ubuntu LXC and run the app there instead of on the host

## Repository Layout

```text
server.js
public/index.html
package.json
setup.sh
LICENSE
README.md
```

## Install Modes

`setup.sh` supports two main install paths:

### 1. Ubuntu / Debian Host Install

This installs directly on the current Ubuntu or Debian system.

It will:

1. Install Node.js
2. Install PM2
3. Clone or update the repo
4. Run `npm install`
5. Start the app with PM2
6. Save the PM2 process and configure PM2 startup with systemd

### 2. Proxmox Host Install With Dedicated LXC

This is the recommended path when you run the installer on a Proxmox host.

It will:

1. Detect that it is running on Proxmox
2. Create a dedicated Ubuntu LXC
3. Start the container
4. Download and run `setup.sh` inside the container in host mode
5. Install Node.js and PM2 inside that container
6. Start the app there, instead of leaving it on the Proxmox host itself

So the app lives inside its own LXC, not directly on the host.

## Quick Start After You Upload To GitHub

Replace `YOUR_GITHUB_USER/YOUR_REPO` and the Proxmox host IP:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/setup.sh | sudo bash -s -- --repo https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git --host 192.168.8.12
```

If you run that command on:

- a **Proxmox host**, it will default to **LXC mode**
- a normal **Ubuntu/Debian box**, it will default to **host mode**

## Common Install Commands

### Proxmox host -> create dedicated LXC automatically

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/setup.sh | sudo bash -s -- \
  --repo https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git \
  --host 192.168.8.12
```

### Force install directly on Ubuntu instead of creating an LXC

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/setup.sh | sudo bash -s -- \
  --mode host \
  --repo https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git \
  --host 192.168.8.12
```

### Create a specific LXC ID with custom resources

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/setup.sh | sudo bash -s -- \
  --mode lxc \
  --repo https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git \
  --host 192.168.8.12 \
  --lxc-id 301 \
  --lxc-name proxmox-helper-local \
  --lxc-memory 2048 \
  --lxc-cores 2 \
  --lxc-disk 8
```

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
```

### Important Options

- `--repo`: required when installing from GitHub/raw and especially for LXC mode
- `--host`: default Proxmox host IP/hostname the app will use on first boot
- `--mode host`: install directly on the current Ubuntu/Debian system
- `--mode lxc`: create a dedicated Ubuntu LXC on Proxmox and install inside it
- `--lxc-storage`: storage for the container root disk
- `--lxc-template-storage`: storage where Proxmox keeps downloaded templates, usually `local`

## Runtime

The app runs with PM2.

Useful commands after install:

```bash
pm2 status
pm2 logs proxmox-helper-local
pm2 restart proxmox-helper-local
pm2 save
```

If you installed in LXC mode, useful Proxmox commands are:

```bash
pct status 301
pct enter 301
pct stop 301
pct start 301
```

## Configuration

The backend reads these environment values:

- `PORT`
- `PROXMOX_HOST_IP`

The installer writes those values for you automatically.

The app stores runtime settings and generated SSH keys in:

```text
data/
```

That folder is ignored by git so you do not accidentally upload private keys or host settings.

## Manual Local Run

If you just want to run it yourself without `setup.sh`:

```bash
npm install
PORT=3000 PROXMOX_HOST_IP=192.168.8.12 npm start
```

Then open:

```text
http://YOUR_SERVER_IP:3000
```

## Uploading To GitHub

If you upload through the GitHub website in the browser, make sure these files are included:

- `server.js`
- `public/index.html`
- `package.json`
- `setup.sh`
- `README.md`
- `LICENSE`
- `.gitignore`

Browser upload is fine. The one-line installer runs `setup.sh` with `bash`, so it does not depend on GitHub preserving executable file permissions.

## Notes

- On Proxmox hosts, `setup.sh` defaults to creating a dedicated Ubuntu LXC
- On normal Ubuntu/Debian systems, it installs directly on the current machine
- The current LXC flow expects a GitHub repo URL because the new container downloads `setup.sh` from GitHub raw
