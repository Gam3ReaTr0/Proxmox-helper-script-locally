# Proxmox Helper Local

Install guide for people who want to run this app themselves.

This project gives you a local web UI for browsing, reading, and deploying Community Scripts style Proxmox helper scripts to your own Proxmox host(s).

## What This Installer Does

When you install it, the app can:

- show the script library in a local web UI
- let you read script details before deploying
- let you add one or more Proxmox hosts in Settings
- generate an SSH key for deployment
- deploy scripts over SSH from the web UI

## Recommended Install

If you are running this on a **Proxmox host**, the recommended path is to let the installer create its own **Ubuntu LXC** and install the app there.

That keeps the app off the Proxmox host itself.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s --
```

## What Happens During Install

If you run the installer on a Proxmox host, it will:

1. detect that it is running on Proxmox
2. auto-detect the Proxmox host IP
3. ask which Proxmox host IP/hostname the app should use by default
4. open a small terminal setup wizard for the LXC network settings
5. if you choose static mode, ask for:
   - `IP/CIDR`
   - `gateway`
6. create the Ubuntu LXC
7. install Node.js
8. install PM2
9. install the app
10. start the app automatically

## After Install

At the end, the installer will show the LXC IP and the URL to open in your browser.

It will look like:

```text
http://YOUR_LXC_IP:3000
```

Open that address in your browser.

## First Setup In The App

After the app opens:

1. open **Settings**
2. add your Proxmox host
3. generate the SSH key
4. copy the public key into the Proxmox host's `authorized_keys`
5. save the host settings
6. start deploying from the web UI

## If You Want To Set The LXC IP Yourself In The Command

The installer now uses a small terminal wizard with `whiptail` when possible, but you can also pass the network settings directly.

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --mode lxc \
  --lxc-ip 192.168.8.50/24 \
  --lxc-gateway 192.168.8.1
```

## If You Want To Install Directly On Ubuntu Instead

If you do **not** want the dedicated LXC and want to install directly on an Ubuntu or Debian machine:

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- --mode host
```

## If The Default Proxmox Host IP Needs To Be Set Manually

You can also pass the host IP yourself:

```bash
curl -fsSL https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh | sudo bash -s -- \
  --host 192.168.8.12
```

If you do not pass `--host` on a Proxmox host, the installer tries to detect it automatically.

## Important GitHub URL Note

Use the **raw** file URL for install, not the normal GitHub page URL.

Do not use:

```text
https://github.com/Gam3ReaTr0/Proxmox-helper-script-locally/blob/main/setup.sh
```

Use:

```text
https://raw.githubusercontent.com/Gam3ReaTr0/Proxmox-helper-script-locally/main/setup.sh
```

## Useful Commands After Install

If you installed into an LXC on Proxmox:

```bash
pct status 301
pct enter 301
pct stop 301
pct start 301
```

If you need to manage the app inside the installed system:

```bash
pm2 status
pm2 logs proxmox-helper-local
pm2 restart proxmox-helper-local
pm2 save
```

## Update The App Later

Run the same install command again.

The installer will update the repo, install dependencies if needed, and restart the app.

## Notes

- default app port: `3000`
- on Proxmox, the installer prefers creating a dedicated Ubuntu LXC
- if you run it in a normal terminal, the installer can show a small terminal wizard for the host and LXC network settings
- if you do not choose a static IP, the LXC uses DHCP

## Advanced Options

If you want to customize the install more, `setup.sh` also supports:

```text
--mode <auto|host|lxc>
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
