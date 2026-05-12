# VPS Setup Scripts

Debian 12 first, with Ubuntu support where package and service names match.

This repository helps you do a basic VPS security setup:

- Generate an SSH key on your own computer.
- Copy setup scripts to a fresh VPS.
- Create a non-root sudo user.
- Configure SSH key login.
- Change the SSH port.
- Disable root SSH login by default.
- Disable password SSH login by default.
- Enable UFW firewall.
- Optionally allow HTTP and HTTPS.
- Enable fail2ban.
- Optionally add swap.
- Enable unattended security upgrades.

Important: keep your current root SSH session open until you have tested a second login using the new user, new SSH port, and private key.

## Requirements

On your own computer:

- Git
- OpenSSH Client, including `ssh`, `scp`, and `ssh-keygen`

On the VPS:

- Debian 12, or Ubuntu with similar package names
- Root SSH access for the first setup
- Provider rescue console or web console access, in case you misconfigure SSH

On Windows, run the local commands in PowerShell. CMD also works for most commands, but PowerShell is the recommended path in this README.

## Step 1: Download This Repository

Run this on your own computer:

```powershell
git clone https://github.com/popshit/vps-setup-scripts.git
cd vps-setup-scripts
```

Path rule: there is no fixed required path. The repository is downloaded into whichever folder you run `git clone` from.

Example: if you run it from `C:\Users\YourName`, the repo becomes:

```text
C:\Users\YourName\vps-setup-scripts
```

All later local commands assume your terminal is already inside the `vps-setup-scripts` folder.

## Step 2: Generate A Local SSH Key

Run this on your own computer, not on the VPS.

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\generate-local-key.ps1 my-vps
```

If you see `ssh-keygen.exe failed`, pull the latest repository version and try again:

```powershell
git pull
powershell -ExecutionPolicy Bypass -File .\scripts\generate-local-key.ps1 my-vps
```

macOS, Linux, Git Bash, or WSL:

```bash
bash scripts/generate-local-key.sh my-vps
```

`my-vps` is only an example key name. Use a name that helps you remember the server, such as `blog-prod`, `debian-vps-1`, or `client-api`.

The script prints a public key beginning with `ssh-ed25519`. Save that public key text. You will paste it into the VPS setup script later.

The generated key files are:

```text
~/.ssh/my-vps_ed25519
~/.ssh/my-vps_ed25519.pub
```

On Windows, `~` means your user folder, for example `C:\Users\YourName`.

Private key: `~/.ssh/my-vps_ed25519`

Public key: `~/.ssh/my-vps_ed25519.pub`

Never upload or paste the private key into a VPS setup prompt. Only paste the public key.

## Step 3: Copy The Setup Scripts To The VPS

Run this on your own computer, still inside the `vps-setup-scripts` folder.

These commands are not key generation. They use `scp` to copy two script files from your computer to the VPS:

```powershell
scp .\scripts\setup-vps.sh root@YOUR_SERVER_IP:/root/setup-vps.sh
scp .\scripts\setup-vps-interactive.sh root@YOUR_SERVER_IP:/root/setup-vps-interactive.sh
```

Replace `YOUR_SERVER_IP` with the real VPS IP address.

If this is your first login to the VPS, `scp` usually asks for the VPS root password.

## Step 4: Login To The VPS As Root

Run this on your own computer:

```powershell
ssh root@YOUR_SERVER_IP
```

After this command succeeds, your terminal is operating on the VPS.

## Step 5: Run The Interactive Setup On The VPS

Run this on the VPS:

```bash
chmod +x /root/setup-vps.sh
chmod +x /root/setup-vps-interactive.sh
sudo bash /root/setup-vps-interactive.sh
```

The interactive script asks for:

- New sudo username, default `deploy`
- New SSH port, default `2222`
- Your public SSH key
- Whether to create swap
- Swap size, default `2G`
- Whether to allow HTTP on port `80`
- Whether to allow HTTPS on port `443`
- Whether to enable fail2ban
- Whether to enable unattended security upgrades
- Whether to temporarily keep root SSH login
- Whether to temporarily keep password SSH login
- Whether to reset existing UFW firewall rules

When asked for the SSH public key, paste the public key from Step 2. It should start with `ssh-ed25519`.

## Step 6: Test The New Login

Do not close the old root SSH session yet.

Open a new terminal on your own computer and test:

```powershell
ssh -i ~/.ssh/my-vps_ed25519 -p 2222 deploy@YOUR_SERVER_IP
```

Adjust the command if you chose a different key name, SSH port, or sudo username.

If this login works, the new user and SSH key are ready.

## Non-Interactive Usage

For automation, run `setup-vps.sh` directly on the VPS:

```bash
sudo /root/setup-vps.sh \
  --user deploy \
  --ssh-port 2222 \
  --public-key "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY" \
  --swap-size 2G \
  --allow-http \
  --allow-https
```

By default, password SSH login is disabled. To temporarily keep password SSH login enabled, add:

```bash
--keep-password-ssh
```

## HTTP And HTTPS Firewall Options

`--allow-http` opens port `80/tcp`. This is used for normal unencrypted web traffic and for some certificate verification flows.

`--allow-https` opens port `443/tcp`. This is used for encrypted website and API traffic.

If the VPS is only for SSH, scripts, databases behind private access, or learning Linux, keep both closed. If the VPS will run a website, reverse proxy, public API, or Let's Encrypt certificate flow, open the one you need. Most public websites eventually need both `80` and `443`.

## What The Main Script Changes

`scripts/setup-vps.sh` does the actual server changes:

- Creates or updates the sudo user.
- Installs your public key into that user's `authorized_keys`.
- Writes SSH config to `/etc/ssh/sshd_config.d/99-vps-setup.conf`.
- Validates SSH config with `sshd -t`.
- Reloads SSH.
- Configures UFW.
- Configures fail2ban.
- Optionally creates swap.
- Enables unattended security upgrades.

## Notes For Linux Beginners

SSH is the remote login service. This setup switches SSH from password login to key login by default.

UFW is a simple firewall frontend. It blocks inbound connections except the ports you allow.

fail2ban watches login failures and temporarily bans abusive IP addresses.

Swap is disk-backed emergency memory. It helps small VPS instances survive memory spikes, but it is much slower than real RAM.

The new sudo user is safer for daily administration than logging in directly as root.

## Recovery Advice

Cloud providers usually offer a web console, recovery mode, or rescue boot. Before running any SSH setup script, confirm you know where that feature is in your VPS control panel.

Do not close your existing root SSH session until the new login command succeeds.
