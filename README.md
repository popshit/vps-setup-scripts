# VPS Hardening Scripts

Debian 12 first, with Ubuntu support where the package and service names match.

This repository gives you two scripts:

- `scripts/generate-local-key.sh`: run on your own computer to create an SSH key pair.
- `scripts/harden-vps.sh`: run as `root` on a fresh Debian 12 or Ubuntu VPS to create a sudo user, install security tools, configure SSH key login, enable UFW, enable fail2ban, and optionally add swap.
- `scripts/harden-vps-interactive.sh`: run on the VPS if you prefer a question-and-answer setup instead of typing all arguments manually.

The most important safety rule: keep the current SSH session open until you have tested a second login using the new user, new SSH port, and private key.

## What The Script Changes

`scripts/harden-vps.sh` can do the following:

- Create a new sudo user.
- Install your public key into that user's `authorized_keys`.
- Configure SSH with a drop-in file under `/etc/ssh/sshd_config.d/`.
- Move SSH to a custom port.
- Disable root SSH login.
- Disable password SSH login.
- Install and enable UFW.
- Allow the new SSH port through UFW.
- Optionally allow HTTP and HTTPS.
- Install and configure fail2ban for SSH.
- Add a swap file.
- Enable unattended security upgrades.

The script validates SSH config with `sshd -t` before reloading SSH.

## Step 1: Generate A Local SSH Key

Run this on your own computer, not on the VPS:

```bash
bash scripts/generate-local-key.sh vps-debian12
```

On Windows PowerShell, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\generate-local-key.ps1 vps-debian12
```

It prints a public key beginning with `ssh-ed25519`. You will pass that public key into the VPS hardening script.

The private key stays on your computer under `~/.ssh`.

## Step 2: Copy The Server Script To The VPS

From your own computer:

```bash
scp scripts/harden-vps.sh root@YOUR_SERVER_IP:/root/harden-vps.sh
scp scripts/harden-vps-interactive.sh root@YOUR_SERVER_IP:/root/harden-vps-interactive.sh
```

Then SSH into the VPS as root:

```bash
ssh root@YOUR_SERVER_IP
```

## Step 3: Run The Hardening Script

For beginners, the interactive version is easiest:

```bash
chmod +x /root/harden-vps.sh
chmod +x /root/harden-vps-interactive.sh
sudo /root/harden-vps-interactive.sh
```

It asks for the new user, SSH port, public key, swap size, and yes/no choices for firewall ports and security tools.

For repeatable automation, use explicit arguments:

Example for Debian 12:

```bash
chmod +x /root/harden-vps.sh
sudo /root/harden-vps.sh \
  --user deploy \
  --ssh-port 2222 \
  --public-key "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY" \
  --swap-size 2G \
  --allow-http \
  --allow-https
```

Use a different SSH port for each VPS if you prefer. Ports from `1024` to `65535` are usually safest for custom SSH.

## Step 4: Test Before Closing The Old Session

Open a new terminal on your own computer:

```bash
ssh -i ~/.ssh/vps-debian12_ed25519 -p 2222 deploy@YOUR_SERVER_IP
```

If this works, your new user and SSH key are ready.

## Recommended Defaults

For a new Debian 12 VPS, this is a sensible baseline:

```bash
sudo /root/harden-vps.sh \
  --user deploy \
  --ssh-port 2222 \
  --public-key "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY" \
  --swap-size 2G \
  --allow-http \
  --allow-https
```

If the VPS will not host a website yet, omit `--allow-http` and `--allow-https`.

## HTTP And HTTPS Firewall Options

`--allow-http` opens port `80/tcp`. This is used for normal unencrypted web traffic and for some certificate verification flows.

`--allow-https` opens port `443/tcp`. This is used for encrypted website and API traffic.

If the VPS is only for SSH, scripts, databases behind private access, or learning Linux, keep both closed. If the VPS will run a website, reverse proxy, public API, or Let's Encrypt certificate flow, open the one you need. Most public websites eventually need both `80` and `443`.

## Notes For Linux Beginners

SSH is the remote login service. The script switches it from password login to key login.

UFW is a simple firewall frontend. It blocks inbound connections except the ports you allow.

fail2ban watches login failures and temporarily bans abusive IP addresses.

Swap is disk-backed emergency memory. It helps small VPS instances survive memory spikes, but it is much slower than real RAM.

The new sudo user is safer for daily administration than logging in directly as root.

## Recovery Advice

Cloud providers usually offer a web console, recovery mode, or rescue boot. Before running any SSH hardening script, confirm you know where that feature is in your VPS control panel.

Do not close your existing root SSH session until the new login command succeeds.
