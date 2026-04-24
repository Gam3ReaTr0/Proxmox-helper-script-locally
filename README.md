# Proxmox Helper Local

Local Community Scripts style UI for browsing, reading, and deploying Proxmox Helper Scripts to one or more Proxmox hosts over SSH.

## What This Repo Includes

- Local script library UI
- Detail/read pages similar to the official site
- Deploy terminal with normal SSH or persistent reconnect mode
- Per-host settings, SSH auth options, and generated SSH key support
- `setup.sh` installer for GitHub-based automated setup

## Local Run

```bash
npm install
npm start
```

Then open:

```text
http://YOUR_SERVER_IP:3000
```

## One-Line Install After Uploading To GitHub

Replace `YOUR_GITHUB_USER/YOUR_REPO` and the Proxmox host IP:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/setup.sh | sudo bash -s -- --repo https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git --host 192.168.8.12
```

That installer will:

1. Install the required system packages
2. Clone or update the repo
3. Run `npm install`
4. Create a systemd service
5. Start the app automatically

## setup.sh Options

```bash
sudo bash setup.sh --host 192.168.8.12
sudo bash setup.sh --host 192.168.8.12 --port 3000
sudo bash setup.sh --repo https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git --dir /opt/proxmox-helper-local
sudo bash setup.sh --host 192.168.8.12 --no-service
```

Supported flags:

- `--repo <git-url>`: GitHub repo to clone/update
- `--dir <path>`: install directory, default `/opt/proxmox-helper-local`
- `--branch <name>`: git branch, default `main`
- `--host <ip-or-hostname>`: default Proxmox host IP for first boot
- `--port <port>`: app port, default `3000`
- `--no-service`: install dependencies only, do not create/start a systemd service

## GitHub Upload

From this folder:

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git
git push -u origin main
```

If you want `setup.sh` to keep its executable bit in git, run this before the first push:

```bash
git update-index --chmod=+x setup.sh
```

## Notes

- App settings and generated SSH keys are stored in `data/`
- `data/` is ignored by git so you do not accidentally upload host settings or private keys
- The backend reads `PORT` and `PROXMOX_HOST_IP` from environment variables
