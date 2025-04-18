# Foundry Automated Install
A fully interactive, production-ready installer script for setting up a dedicated [Foundry VTT](https://foundryvtt.com) server on Ubuntu Linux.

Created by [TripodGG](https://github.com/TripodGG)  
Current Version: **v2.0**

---

## 💡 Features

- 📦 Automatic installation of:
  - Node.js 20
  - PM2 process manager
  - Caddy reverse proxy with HTTPS
  - Foundry VTT server
- 🌍 Reverse proxy support with domain + port prompt
- ⚙️ PM2 autostart and crash recovery
- 🔁 Full `options.json` regeneration with backup and restore fallback
- 🧠 RAM-based swapfile recommendations and setup
- 📝 Full logging of every step, with timestamps
- ❓ Interactive prompts with smart defaults

---

## 🧰 Requirements

- Ubuntu Server 20.04 or later
- A valid Foundry VTT download link
- A public domain pointed at your server (for Caddy to use)

---

## 🚀 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/TripodGG/Foundry-Automated-Install.git
   cd Foundry-Automated-Install
   ```
2. Make the script executable:
   ```bash
   sudo chmod +x foundry-install.sh
   ```
3. Execute the script:
   ```bash
   ./foundry-install.sh
   ```