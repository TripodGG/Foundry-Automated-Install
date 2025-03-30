# 🛠️ Foundry Automated Game Server Install

A shell script to automate the setup of a dedicated [Foundry Virtual Tabletop](https://foundryvtt.com/) server on **Ubuntu Linux**.

> **Author:** [TripodGG](https://github.com/TripodGG)  
> **Repo:** [github.com/TripodGG/Foundry-Automated-Install](https://github.com/TripodGG/Foundry-Automated-Install)  
> **Version:** 1.0

---

## 🚀 Features

- ✅ Installs Node.js 20.x (compatible with Foundry VTT)
- ✅ Installs Caddy web server (for optional HTTPS support)
- ✅ Installs PM2 for future process management
- ✅ Creates proper user-based directory structure
- ✅ Downloads Foundry VTT from a user-provided URL
- ✅ Offers to clean up the installation ZIP
- ✅ Starts Foundry using your specified data path

---

## 🧰 Requirements

- Ubuntu 20.04 or newer
- A valid Foundry VTT license with access to the download URL
- Sudo/root privileges

---

## 📦 Installation

### 1. Clone this repository

```bash
git clone https://github.com/TripodGG/Foundry-Automated-Install.git
cd Foundry-Automated-Install
chmod +x foundry-install.sh
./foundry-install.sh