# Foundry‑Automated‑Install

Automated, single or multi‑instance **Foundry VTT** installer for Ubuntu. It provisions:

* Reverse proxy with **Caddy** (TLS on ports 80/443, per‑instance hostnames)
* **Foundry** instances managed by **PM2** (Node.js)
* A browser-based file manager via **elFinder** behind **Apache** on `localhost:29999`
* Sensible defaults, idempotent checks, and a quiet logging mode

> Current script version: **v4.4**

---

## ⚙️ What it does

* Installs/updates required packages: Caddy, Node.js 20, PM2, Apache, PHP/Composer, unzip, etc.
* Sets up base folders: `~/foundryvtt` (app), `~/foundrydata/<instance>` (data)
* Prompts for **instance name**, **public URL** (e.g., `mygame.example.com`), and **port**

  * Auto‑suggests the next free port (30001+), verifies it isn’t used or already in Caddy
* Downloads and unzips Foundry (if the install dir is empty)
* Writes a **Caddy** site block per instance and restarts Caddy
* Creates `Config/options.json` for the instance
* Starts the app with **PM2**, saves the process list
* Installs elFinder file manager (if missing) and configures an Apache vhost on `*:29999`

  * Adds a Caddy block with **basicauth** (hashed via `caddy hash-password`)
* Optionally creates/activates a swapfile

---

## 🧱 Architecture overview

```
Internet
   │
   ▼
Caddy :80 / :443  ──────► reverse_proxy ►  Foundry Instance A :30001 (PM2)
   │                                      Foundry Instance B :30002 (PM2)
   │
   └──────────────► reverse_proxy ►  Apache :29999  ─► elFinder file manager
```

* **Caddy** owns **80/443** and terminates TLS for your public hostnames
* **Foundry** instances listen on high ports (30001+), supervised by **PM2**
* **Apache** only listens on **29999** (local); Caddy proxies `/` for your file manager hostname to `localhost:29999`

---

## ✅ Requirements

* A recent Ubuntu LTS (tested on current LTS releases)
* A **non‑root** user with `sudo` privileges (a dedicated user is recommended)
* **DNS A/AAAA** records for each Foundry instance hostname (and for the file manager hostname) pointing to this server
* Outbound internet access (package repos, NodeSource, Caddy repo, Foundry download)
* Your **Foundry download URL** (from your licensed account)

> The script intentionally **must not** be run as `root`. Use your sudo‑enabled user.

---

## 🚀 Quick start

```bash
# 1) Clone this repo
git clone https://github.com/TripodGG/Foundry-Automated-Install.git
cd Foundry-Automated-Install

# 2) Make the installer executable
chmod +x foundryinstall.sh

# 3) Run it
./foundryinstall.sh
```

You’ll be prompted for:

* **Username** (defaults to your current user)
* **Instance name** (e.g. `campaign1`)
* **Public URL** (e.g. `game.example.com`)
* **App port** (accept the suggested free port, or enter your own)
* **File Explorer hostname**, **username**, **password**
* **Swap size** (accept the suggested size, or enter your own in GB)

At the end, you’ll see the access URL for your new instance.

> To create another instance, run the script again and provide a new instance name + hostname. The script de‑duplicates hostnames and ports.

---

## 🧭 File & directory layout

* **App install**: `~/foundryvtt`
* **Per‑instance data**: `~/foundrydata/<instanceName>`
* **Instance config**: `~/foundrydata/<instanceName>/Config/options.json`
* **Caddy config**: `/etc/caddy/Caddyfile` (a site block per instance + a file‑manager block)
* **Apache vhost**: `/etc/apache2/sites-available/elfinder.conf` (enabled)
* **Installer log**: `~/Foundry-Automated-Install/install.log`

---

## 🔇 Logging & console output (Quiet mode)

The installer runs in **quiet mode**:

* All command output goes to: `~/Foundry-Automated-Install/install.log`
* Only curated messages and prompts appear on screen
* Toggle extra on‑screen logs by setting `VERBOSE=true` inside the script if desired

```bash
# Inspect logs
less -R ~/Foundry-Automated-Install/install.log
```

---

## 🧰 Managing instances with PM2

Common PM2 commands:

```bash
# List instances
pm2 list

# List processes
pm2 status

# View logs for one instance
pm2 logs <instanceName>

# Start/stop/restart all instances
pm2 start all
pm2 stop all
pm2 restart all

# Restart/stop/delete an instance
pm2 restart <instanceName or IDnumber>
pm2 stop <instanceName or IDnumber>
pm2 delete <instanceName or IDnumber>

# Save the current process list for startup
pm2 save
```

The script starts each instance as:

```
node ~/foundryvtt/resources/app/main.js --dataPath=~/foundrydata/<instanceName>
```

---

## 🔐 File manager (elFinder)

* Served locally by **Apache** on `localhost:29999`
* Exposed publicly behind **Caddy** at the hostname you provide during install
* Protected with **HTTP Basic Auth** (password hashed with `caddy hash-password`)

**Change file‑manager credentials later**

1. Generate a new hash: `caddy hash-password`
2. Update the `basicauth` line inside the file‑manager block in `/etc/caddy/Caddyfile`
3. `sudo systemctl restart caddy`

---

## 🔧 Troubleshooting

**Apache fails to start: “Address already in use :80”**

* Ensure Apache is **not** listening on 80/443. The installer comments out those in `/etc/apache2/ports.conf` and adds `Listen 29999`.
* Validate:

  ```bash
  sudo apachectl -S
  sudo apachectl configtest
  sudo ss -ltnp | grep -E ':(80|443|29999)\b' || true
  ```

**Caddy fails to reload or no TLS certificate**

* Confirm DNS for your hostname points to this server and ports 80/443 are reachable
* Check logs:

  ```bash
  journalctl -u caddy --no-pager -e
  ```

**Port conflicts**

* The script checks Caddyfile and the system listeners before accepting a port. To inspect manually:

  ```bash
  sudo ss -ltnp | sort -k4
  ```

**Foundry didn’t download**

* Ensure your licensed download URL is valid (they can expire). Rerun the script or place the zip as `~/foundryvtt/foundryvtt.zip`.

---

## ♻️ Updating / re‑running

* Safe to re‑run for **additional instances**; the script protects against duplicate hostnames and ports.
* For package updates (Node/Caddy/etc.), re‑running will reinstall dependencies if needed.

---

## 🧹 Removing an instance (manual steps)

1. Stop & remove the PM2 process:

   ```bash
   pm2 stop <instanceName> && pm2 delete <instanceName> && pm2 save
   ```
2. Remove the Caddy block for that hostname from `/etc/caddy/Caddyfile`, then:

   ```bash
   sudo systemctl restart caddy
   ```
3. (Optional) Remove data: `sudo rm -rf ~/foundrydata/<instanceName>`

> A scripted uninstaller is on the roadmap.

---

## 🗺️ Roadmap

* Built‑in uninstall / instance removal
* Preflight checks & summary (ports, binaries, perms)
* Caddyfile backup & validation pre‑edit

---

## 🤝 Contributing

PRs welcome! If you hit an edge case, open an issue with:

* OS version, what you ran, expected vs. actual, and relevant log excerpts from `install.log`

---

## 📄 License

MIT License — Copyright (c) 2025 TripodGG
