# 🧙‍♂️ Foundry VTT Multi-Instance Installer

A fully automated, production-ready **multi-instance** installer for [Foundry Virtual Tabletop](https://foundryvtt.com) on Ubuntu Linux.  
Easily deploy multiple isolated instances of Foundry VTT with custom domains, ports, and automatic reverse proxy support via **Caddy** and process management through **PM2**.

Created with 🧠, ☕, and some 🎲 by [TripodGG](https://github.com/TripodGG)  
Current Version: **v3.1**

---

## 🚀 Features

- 🛠️ **Fully interactive install script** — prompts you for instance name, download URL, domain, and port
- 📁 **Isolated directory structure** — each instance lives in its own folder with its own data, logs, and configs
- 🌐 **Folder access via web** — Upload all your data with ease to each game instance with FileGator
- 🔐 **Caddy reverse proxy support** — automatic HTTPS using your own domain/subdomain
- ⚙️ **PM2 process manager** — auto-start, monitoring, and crash recovery
- 📦 **Node.js installed**
- 🧠 **Swap file management** — detects RAM and recommends a swap size, you decide to go with the recommended value, the default value, or something else, then creates the swap file for you
- 📝 **Full logging** — every step is timestamped and saved per instance
- 💥 **Auto-recovery & validation** — includes checks for download success, Foundry startup confirmation, and more
- 🔄 **Safe re-runs** — smart detection prevents duplicate Caddy entries and overwriting config files
- ✅ **Tested on Ubuntu 22.04+**

---

## 📦 Requirements

- Ubuntu 20.04 or later
- Valid **Foundry VTT** licenses and download link
- A domain or subdomain pointed to your server (e.g. `campaign1.yourdomain.com`)
- HTTP/HTTPS Port access
- Sudo privileges

---

## 📂 Folder Structure
Single Instance:
```
/home/youruser/
├── campaign1/              # Instance name becomes the root folder
│   ├── foundryvtt/         # Foundry application files
│   ├── data/               # Instance-specific data (with shared modules)
│   └── log/                # Install and runtime logs
└── modules/                # Shared Foundry modules directory (symlinked)
```
Two Instances:
```
/home/youruser/
|
├── campaign1/              # Instance name becomes the root folder
│   ├── foundryvtt/         # Foundry application files
│   ├── data/               # Instance-specific data (with shared modules)
│   └── log/                # Install and runtime logs
|
├── campaign2/              # Instance name becomes the root folder
│   ├── foundryvtt/         # Foundry application files
│   ├── data/               # Instance-specific data (with shared modules)
│   └── log/                # Install and runtime logs
|
└── modules/                # Shared Foundry modules directory (symlinked)
```
Additional folders are created for each instance (campaign3/, campaign4/, and so on)

---

## 📋 How It Works

1. You run the script.
2. You're prompted to:
   - Name your instance
   - Provide the Foundry VTT download URL
   - Assign a custom domain and port
3. Script installs dependencies and unzips Foundry
4. A symlink is created from `instance/data/Data/modules` to the global `~/modules` folder
5. A test run of Foundry is performed and confirmed
6. A PM2 process is created and saved
7. Caddy is configured and restarted with the new domain
8. `options.json` is generated
9. A swapfile is created based on memory size or a default value

---

## 🧰 Installation

```bash
git clone https://github.com/TripodGG/Foundry-Multi-instance-Install.git
cd Foundry-Multi-instance-Install
chmod +x foundry-install.sh
./foundry-install.sh
```

Run the script again for each additional instance you want to deploy.

---

## 🔁 Example Re-run

```bash
./foundry-install.sh
```

You’ll be prompted to enter a new instance name, domain, and port, and the script will create a new folder structure and symlinks.

---

## 🛠 Troubleshooting

If you encounter errors:
- Check the log file created in `~/yourInstanceName/log/install.log`
- Make sure ports aren’t reused
- Ensure DNS records are in place, proxied, and propagated

---

## ❤️ Acknowledgments

Built with ❤️ by [TripodGG](https://github.com/TripodGG). Inspired by the Foundry community.

---

## 🧪 Future Goals

- Single run install for all desired instances
- Web UI for managing instances
- Instance update automation
- Backup and restore options

---