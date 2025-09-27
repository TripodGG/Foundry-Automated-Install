#!/bin/bash
# Name: Foundry Multi-Instance Installer
# Author: TripodGG
# Purpose: Automate single or multi-instance Foundry VTT setup on Ubuntu 
# License: MIT License, Copyright (c) 2025 TripodGG




# ==========================
# Configuration & Early Input
# ==========================
scriptVersion="4.4"
set -euo pipefail
IFS=$'\n\t'

# Colors for on-screen messages
red='\033[0;31m'
yellow='\033[33m'
green='\033[0;32m'
undo='\033[0m'

# Determine user/home; prompt BEFORE redirecting output so this prompt is visible
detectedUser="$(whoami)"
read -p "Enter your username [${detectedUser}]: " username
username=${username:-$detectedUser}
currentUser="$username"
homeDir="$(eval echo "~$currentUser")"
clear

# Log file (ensure directory exists)
logFile="$homeDir/Foundry-Automated-Install/install.log"
mkdir -p "$(dirname "$logFile")"
touch "$logFile"

# Quiet mode: route all stdout/stderr to the log; keep FD 3/4 for console
exec 3>&1 4>&2
exec >>"$logFile" 2>&1

# Verbose toggle for duplicating logs to console when desired
VERBOSE=false



# ==========================
# Helpers (console + logging)
# ==========================
ui()   { printf "%b\n" "$*" >&3; }
ok()   { printf "%b\n" "${green}$*${undo}" >&3; }
warn() { printf "%b\n" "${yellow}$*${undo}" >&3; }
err()  { printf "%b\n" "${red}$*${undo}" >&3; }

prompt() {                # prompt "Question: " VAR
  printf "%s" "$1" >&3
  read -r "$2" < /dev/tty
}
prompt_default() {        # prompt_default "Question" VAR DEFAULT
  local __msg="$1" __var="$2" __def="$3" __in=""
  printf "%s [%s]: " "$__msg" "$__def" >&3
  read -r __in < /dev/tty
  if [ -z "$__in" ]; then eval "$__var=\"\$__def\""; else eval "$__var=\"\$__in\""; fi
}
prompt_secret() {         # prompt_secret "Secret: " VAR
  printf "%s" "$1" >&3
  stty -echo < /dev/tty
  read -r "$2" < /dev/tty
  stty echo < /dev/tty
  printf "\n" >&3
}
any_key() {               # any_key "Press any key..."
  printf "%s" "$1" >&3
  read -r -n 1 _junk < /dev/tty
  printf "\n" >&3
}

log() {                   # log only to file; optionally duplicate when VERBOSE=true
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf "[%s] %s\n" "$ts" "$1"
  if [ "${VERBOSE:-false}" = true ]; then printf "[%s] %s\n" "$ts" "$1" >&3; fi
}

# Port helpers for Caddy/system
port_in_caddy() {
  local p="$1" caddyFile="/etc/caddy/Caddyfile"
  [ -f "$caddyFile" ] || return 1
  grep -qE "localhost:${p}([^0-9]|$)" "$caddyFile"
}
port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE "(:|\\.)${p}\$"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk '{print $9}' | grep -qE "(:|\\.)${p}\$"
  else
    return 1
  fi
}
find_next_free_port() {
  local from_port=30001
  local to_port=65000

  # Accept 0, 1, or 2 args without touching unset params (set -u safe)
  if [ $# -ge 1 ]; then from_port="$1"; fi
  if [ $# -ge 2 ]; then to_port="$2"; fi

  local p="$from_port"
  while [ "$p" -le "$to_port" ]; do
    if ! port_in_caddy "$p" && ! port_in_use "$p"; then
      printf '%s\n' "$p"
      return 0
    fi
    p=$((p + 1))
  done
  return 1
}

valid_port() { local p="$1"; [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]; }

# elFinder block detector
elfinder_block_exists() {
  local caddyFile="/etc/caddy/Caddyfile" hostPort="$1"
  [ -f "$caddyFile" ] || return 1
  grep -qE '^[[:space:]]*# elFinder reverse proxy for file manager' "$caddyFile" && return 0
  grep -qE "[[:space:]]reverse_proxy[[:space:]]+localhost:${hostPort}([^0-9]|$)" "$caddyFile"
}



# ==========================
# Guardrails & Greeting
# ==========================
if [ "$EUID" -eq 0 ]; then
  err "This script must NOT be run as root."
  exit 1
fi

cat >&3 <<'EOF'

   ____                  __           _   ______________
  / __/__  __ _____  ___/ /_____ __  | | / /_  __/_  __/
 / _// _ \/ // / _ \/ _  / __/ // /  | |/ / / /   / /   
/_/  \___/\_,_/_//_/\_,_/_/  \_, /   |___/ /_/   /_/    
        ____         __     /___/_                      
       /  _/__  ___ / /____ _/ / /__ ____               
      _/ // _ \(_-</ __/ _ `/ / / -_) __/               
     /___/_//_/___/\__/\_,_/_/_/\__/_/                  
                                                        

EOF
ui "Welcome, $currentUser, to the Foundry VTT Multi-Instance Installer"
ui "----------------------------------------------"
ui "This installer will prompt you for basic information about your Foundry instance."
ui "It is recommended that you use a dedicated user separate from your own to host Foundry VTT."
any_key "Press any key to begin the initial setup process..."
ok  "Beginning installation. Please wait..."
log "🚀 Starting FoundryVTT install script (v$scriptVersion) for user $currentUser"



# ==========================
# System Prep & Packages
# ==========================
log "Updating system packages (base)..."
warn "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Caddy repo & NodeSource
sudo mkdir -p /etc/apt/keyrings
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg ca-certificates

if [ ! -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg ]; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  log "Caddy GPG key added"
else
  log "Caddy GPG key already exists, skipping"
fi
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
curl -sL https://deb.nodesource.com/setup_20.x | sudo bash -

sudo apt update
log "Installing dependencies..."
warn "Installing dependencies..."
sudo apt install -y unzip net-tools libssl-dev nodejs apache2 git php composer caddy
sudo npm install -g pm2



# ==========================
# elFinder File Manager
# ==========================
ui  "Checking for File Manager installation."
log "Checking for elFinder file manager installation."
if [ ! -d "/var/www/elFinder-2.1.64" ]; then
  ui  "File Manager not found. Installing..."
  log "elFinder file manager not found. Installing..."

  pushd /var/www >/dev/null
  sudo wget -O elFinder.zip https://github.com/Studio-42/elFinder/archive/refs/tags/2.1.64.zip
  sudo unzip -o elFinder.zip && sudo rm elFinder.zip

  sudo mv /var/www/elFinder-2.1.64/elfinder.html /var/www/elFinder-2.1.64/index.html
  sudo cp "$homeDir/Foundry-Automated-Install/connector.minimal.php" /var/www/elFinder-2.1.64/php/connector.minimal.php
  sudo cp "$homeDir/Foundry-Automated-Install/roots.config.php"      /var/www/elFinder-2.1.64/php/roots.config.php
  sudo chown -R "$currentUser:$currentUser" /var/www/elFinder-2.1.64
  popd >/dev/null

  # vhost for port 29999 (no ports.conf edits here)
  sudo tee /etc/apache2/sites-available/elfinder.conf > /dev/null <<'APACHECONF'
<VirtualHost *:29999>
    DocumentRoot /var/www/elFinder-2.1.64
</VirtualHost>
APACHECONF

  sudo a2ensite elfinder.conf >/dev/null

  ok  "File Manager installation complete."
  log "elFinder file manager installation complete."
else
  ui  "File Manager already installed. Skipping installation."
  log "elFinder file manager already installed. Skipping installation."
fi



# ==========================
# Apache Ports Harmonization (Caddy owns :80/:443)
# ==========================
portsconf="/etc/apache2/ports.conf"
log "Ensuring Apache is not binding to :80/:443 (reserved for Caddy) and is listening on :29999."

# Comment out default HTTP/HTTPS listens
if grep -qE '^\s*Listen\s+80\b' "$portsconf"; then
  sudo sed -i -E 's/^\s*Listen\s+80\b/# Disabled by Foundry installer: Listen 80/' "$portsconf"
  log "Commented out 'Listen 80' in $portsconf"
fi
if grep -qE '^\s*Listen\s+443\b' "$portsconf"; then
  sudo sed -i -E 's/^\s*Listen\s+443\b/# Disabled by Foundry installer: Listen 443/' "$portsconf"
  log "Commented out 'Listen 443' in $portsconf"
fi

# Ensure port 29999 is present
if ! grep -qE '^\s*Listen\s+29999\b' "$portsconf"; then
  echo 'Listen 29999' | sudo tee -a "$portsconf" > /dev/null
  log "Added 'Listen 29999' to $portsconf"
fi

# Disable any enabled vhost that binds to :80 or :443
for site in /etc/apache2/sites-enabled/*.conf; do
  if grep -qE '<VirtualHost\s+\*:(80|443)>' "$site"; then
    sudo a2dissite "$(basename "$site")" > /dev/null || true
    log "Disabled site $(basename "$site") because it binds to :80 or :443"
  fi
done

# Validate and apply
if ! sudo apachectl configtest; then
  err "Apache config test failed. See $logFile"
  exit 1
fi
sudo systemctl reload apache2 || true



# ==========================
# Instance Basics & Folders
# ==========================
prompt "Enter a unique name for this instance (e.g., campaign1): " instanceName
if [[ -z "$instanceName" ]]; then
  err "❌ Instance name cannot be empty."
  log "❌ Instance name cannot be empty."
  exit 1
fi

log "Creating required directories..."
warn "Creating required directories..."
for folder in "$homeDir/foundryvtt" "$homeDir/foundrydata"; do
  if [ -d "$folder" ]; then
    ui  "$folder already exists. Skipping"
    log "$folder already exists. Skipping"
  else
    ui  "Creating folder: $folder"
    log "Creating folder: $folder"
    mkdir -p "$folder"
  fi
done

installDir="$homeDir/foundryvtt"
dataDir="$homeDir/foundrydata/$instanceName"
sudo mkdir -p "$dataDir"
ok  "Instance directories created successfully."
log "$dataDir directory created successfully"
log "Foundry Install Started"
log "Installer version: $scriptVersion"
log "Instance name: $instanceName"



# ==========================
# Foundry Download / Unzip
# ==========================
filename="$installDir/foundryvtt.zip"

if [ -z "$(ls -A "$installDir" 2>/dev/null)" ]; then
  warn "No data found in $installDir"
  prompt "Enter your Foundry VTT download URL: " foundryUrl

  if [ -n "$foundryUrl" ]; then
    log "Downloading Foundry VTT"
    warn "Downloading Foundry VTT..."
    cd "$installDir" || { log "Failed to enter $installDir"; err "❌ See $logFile"; exit 1; }
    sudo wget -O "$filename" "$foundryUrl" || { log "❌ Download failed. URL expired?"; err "❌ See $logFile"; exit 1; }
    log "Download complete: $filename"
    ok  "Download complete."
  else
    ui  "No URL provided. Exiting."
    exit 1
  fi
else
  log "Foundry VTT install found. Skipping download."
fi

if [ -f "$filename" ]; then
  warn "Unzipping Foundry VTT to $installDir..."
  warn "This may take some time. Please wait..."
  log "Unzipping $filename..."
  sudo unzip -o "$filename" -d "$installDir" || { log "❌ Failed to unzip archive."; err "❌ See $logFile"; exit 1; }
else
  log "No archive found at $filename. Skipping unzip."
fi

if [ -f "$installDir/resources/app/main.js" ]; then
  sudo chmod 755 "$installDir/resources/app/main.js"
  log "Ensured $installDir/resources/app/main.js is now executable."
fi
ok  "Foundry VTT install complete."

deleteZip="false"
prompt_yes_no() { # reuse a tiny yes/no specifically for this one question
  local q="$1" var="$2" ans=""
  printf "%s (y/n) [n]: " "$q" >&3
  read -r ans < /dev/tty
  ans="${ans,,}"
  if [[ -z "$ans" || "$ans" =~ ^(n|no)$ ]]; then eval "$var=false"
  elif [[ "$ans" =~ ^(y|yes)$ ]]; then eval "$var=true"
  else
    ui "Invalid input. Please answer 'y' or 'n'."
    prompt_yes_no "$q" "$var"
  fi
}
prompt_yes_no "Would you like to delete the Foundry ZIP file to save space?" deleteZip
if [ "$deleteZip" = true ] && [ -f "$filename" ]; then
  sudo rm -f "$filename"
  log "$(basename "$filename") deleted"
else
  log "$(basename "$filename") retained (or not present)"
fi



# ==========================
# Caddyfile Prep & Cleanup
# ==========================
caddyFile="/etc/caddy/Caddyfile"
hostPort="29999"

sudo touch "$caddyFile"
log "Clearing Caddyfile legacy blocks if present..."
if grep -q '^:80[[:space:]]*{' "$caddyFile"; then
  sudo sed -i '/^:80[[:space:]]*{/,/^[[:space:]]*}/d' "$caddyFile"
  log "Removed :80 block from Caddyfile."
else
  log "No :80 block found. Nothing to do."
fi



# ==========================
# URL & Port Prompts
# ==========================
while :; do
  prompt "Enter the URL that will be used for this instance (e.g. gamename.example.com): " instanceUrl
  if [ -z "$instanceUrl" ] || ! [[ "$instanceUrl" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    err  "❌ Invalid URL format. Try again."
    log "❌ Invalid URL format: $instanceUrl"
    continue
  fi
  if grep -qE "^[[:space:]]*${instanceUrl}[[:space:]]*\\{" "$caddyFile"; then
    warn "⚠️ $instanceUrl already exists in $caddyFile. Enter a different URL."
    log  "⚠️ $instanceUrl already exists in $caddyFile"
    continue
  fi
  break
done

suggestedPort="$(find_next_free_port 30001 65000 || echo 30001)"
while :; do
  printf "Enter the port number to use for this instance (e.g. 30001, 30002) [%s]: " "$suggestedPort" >&3
  read -r instancePort < /dev/tty
  instancePort="${instancePort:-$suggestedPort}"

  if ! valid_port "$instancePort"; then
    err "❌ Invalid port. Please enter a value between 1025–65535."
    log "❌ Invalid port number: $instancePort"
    continue
  fi
  if port_in_caddy "$instancePort"; then
    warn "⚠️ Port $instancePort already referenced in $caddyFile. Choose a different port."
    log  "⚠️ Port $instancePort already referenced in $caddyFile"
    suggestedPort="$(find_next_free_port $((instancePort + 1)) 65000 || echo 30001)"
    continue
  fi
  if port_in_use "$instancePort"; then
    warn "⚠️ Port $instancePort already in use on this system. Choose a different port."
    log  "⚠️ Port $instancePort appears to be in use"
    suggestedPort="$(find_next_free_port $((instancePort + 1)) 65000 || echo 30001)"
    continue
  fi
  break
done



# ==========================
# Write Instance Caddy Block
# ==========================
caddyEntry="
# FoundryVTT instance: $instanceName
$instanceUrl {
    reverse_proxy localhost:$instancePort
    encode zstd gzip
}
"

if ! grep -qE "^[[:space:]]*${instanceUrl}[[:space:]]*\\{" "$caddyFile"; then
  echo "$caddyEntry" | sudo tee -a "$caddyFile" > /dev/null
  log "✅ Caddyfile entry appended for $instanceUrl on port $instancePort"
  ok  "✅ Added Caddy entry for $instanceUrl (port $instancePort)."
else
  log "ℹ️ Caddyfile already contains an entry for $instanceUrl. Skipping append."
  warn "ℹ️ $instanceUrl already present in $caddyFile. Skipping append."
fi



# ==========================
# File Manager Reverse Proxy (skip prompts if exists)
# ==========================
if elfinder_block_exists "$hostPort"; then
  log  "ℹ️ File manager reverse proxy already configured in $caddyFile. Skipping."
  warn "ℹ️ File manager reverse proxy already configured. Skipping."
else
  prompt "Enter hostname for file manager (e.g., files.example.com): " elFinderhost
  if [[ -z "$elFinderhost" ]]; then
    err "❌ File manager hostname cannot be empty."
    exit 1
  fi
  # Ensure hostname isn't already defined as a site label
  esc_host="$(printf '%s' "$elFinderhost" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g')"
  if grep -qE "^[[:space:]]*${esc_host}[[:space:]]*\\{" "$caddyFile"; then
    warn "⚠️ Host '${elFinderhost}' already defined in $caddyFile. Choose a different hostname."
    log  "⚠️ Host '${elFinderhost}' already defined in $caddyFile"
    exit 1
  fi

  prompt "Enter a username for file manager: " FM_USERNAME
  prompt_secret "Enter a password for file manager: " FM_PASSWORD
  err "Do not lose this information as it cannot be recovered."

  HASH="$(caddy hash-password <<< "$FM_PASSWORD" || true)"
  if [[ -z "${HASH:-}" ]]; then
    log "❌ Failed to generate password hash with caddy hash-password."
    err "❌ An error has occurred while hashing password. See $logFile"
    exit 1
  fi

  log "Appending reverse proxy block for $elFinderhost on port $hostPort..."
  sudo tee -a "$caddyFile" > /dev/null <<EOF

# elFinder reverse proxy for file manager
$elFinderhost {
    reverse_proxy localhost:$hostPort

    basicauth {
        $FM_USERNAME $HASH
    }

    
}
EOF

  if [[ $? -eq 0 ]]; then
    log "✅ Successfully added file manager block"
  else
    log "❌ Failed to append file manager block to $caddyFile."
    err "❌ An error has occurred. See $logFile"
    exit 1
  fi
fi



# ==========================
# Restart Caddy
# ==========================
log "Restarting Caddy service..."
if sudo systemctl restart caddy; then
  log "✅ Caddy restarted successfully"
else
  log "❌ Caddy failed to restart"
  err "❌ An error has occurred. See $logFile"
  exit 1
fi



# ==========================
# Write options.json
# ==========================
configDir="$dataDir/Config"
optionsFile="$configDir/options.json"
backupFile="$configDir/options.json.bak"

sudo mkdir -p "$configDir"
if [ -f "$optionsFile" ]; then
  cp "$optionsFile" "$backupFile"
  log "📦 Existing options.json backed up to options.json.bak"
fi

log "Writing new options.json to $optionsFile..."
sudo tee "$optionsFile" > /dev/null <<EOF
{
  "dataPath": "$dataDir",
  "compressStatic": true,
  "fullscreen": false,
  "hostname": "$instanceUrl",
  "language": "en.core",
  "localHostname": null,
  "port": $instancePort,
  "protocol": null,
  "proxyPort": 443,
  "proxySSL": true,
  "routePrefix": null,
  "updateChannel": "stable",
  "upnp": true,
  "upnpLeaseDuration": null,
  "awsConfig": null,
  "compressSocket": true,
  "cssTheme": "foundry",
  "deleteNEDB": false,
  "hotReload": false,
  "passwordSalt": null,
  "sslCert": null,
  "sslKey": null,
  "world": null,
  "serviceConfig": null
}
EOF

if [ -f "$optionsFile" ]; then
  log "✅ options.json written successfully"
else
  log "❌ Failed to write options.json. Attempting to restore from backup..."
  if [ -f "$backupFile" ]; then
    cp "$backupFile" "$optionsFile"
    log "✅ Restored original options.json from backup"
    ui  "❌ New config failed. Restored previous config file."
  else
    log "❌ No backup available to restore."
    err "❌ An error has occurred. See $logFile"
  fi
  exit 1
fi



# ==========================
# Swap File (optional/once)
# ==========================
memTotalKB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
memTotalGB=$(( (memTotalKB + 1048575) / 1048576 ))
log "System memory detected: ${memTotalGB}GB"

if [ "$memTotalGB" -lt 2 ]; then
  recommendedSwapSize=$((memTotalGB * 2))
elif [ "$memTotalGB" -le 4 ]; then
  recommendedSwapSize=$((memTotalGB + memTotalGB / 2))
elif [ "$memTotalGB" -le 8 ]; then
  recommendedSwapSize=$memTotalGB
else
  recommendedSwapSize=2
fi
log "Recommended swap size: ${recommendedSwapSize}G"

printf "Enter the size of the swapfile in GB (default 2G, recommended: %sG), or press enter if already completed: " "$recommendedSwapSize" >&3
read -r swapSizeInput < /dev/tty
if [ -z "$swapSizeInput" ]; then
  swapSizeGB=2
  log "No swap size entered. Defaulting to 2G"
else
  swapSizeInput=$(echo "$swapSizeInput" | tr '[:lower:]' '[:upper:]')
  swapSizeGB=$(echo "$swapSizeInput" | sed 's/G[B]*$//')
  if ! [[ "$swapSizeGB" =~ ^[0-9]+$ ]]; then
    log "❌ Invalid swap size entered: $swapSizeInput"
    err "❌ Invalid input. Please enter a whole number (e.g. 2 or 2G)"
    err "❌ See $logFile"
    exit 1
  fi
fi
swapSize="${swapSizeGB}G"
log "User selected swap size: $swapSize"

if [ -f /swapfile ]; then
  log "/swapfile already exists. Skipping creation."
else
  log "Creating $swapSize swapfile at /swapfile..."
  sudo fallocate -l "$swapSize" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile && log "Swapfile created and marked as swap space"
  if ! grep -q "^/swapfile" /etc/fstab; then
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null
    log "Swapfile entry added to /etc/fstab"
  else
    log "Swapfile entry already present in /etc/fstab"
  fi
  log "Enabling swapfile..."
  sudo swapon -a
fi

log "Swap status:"
sudo swapon --show



# ==========================
# PM2 Setup (Foundry App)
# ==========================
log "🔧 Preparing PM2 environment..."
ui  "🔧 Configuring PM2..."

startCommand="node $installDir/resources/app/main.js --dataPath=$dataDir"

ui  "Starting PM2 process for $instanceName"
pm2 start "$startCommand" --name "$instanceName" --watch && log "PM2 process '$instanceName' started with watch enabled"
sleep 1
ui  "PM2 process '$instanceName' started with watch enabled"
sleep 1
ui  "Saving PM2 process list..."
pm2 save --force && log "PM2 configuration saved for $instanceName startup"
sleep 1
ui  "PM2 configuration saved for $instanceName startup"

log "Ensuring foundry folders are created (PM2 cycle)"
ui  "Restarting all pm2 processes..."
pm2 start all
pm2 stop all



# ==========================
# Wrap Up
# ==========================
sudo systemctl start apache2
pm2 start all

cat >&3 <<'EOF'

    ____           __        ____            
   /  _/___  _____/ /_____ _/ / /            
   / // __ \/ ___/ __/ __ `/ / /             
 _/ // / / (__  ) /_/ /_/ / / /              
/___/_/_/_/____/\__/\__,_/_/_/ __     __     
  / ____/___  ____ ___  ____  / /__  / /____ 
 / /   / __ \/ __ `__ \/ __ \/ / _ \/ __/ _ \
/ /___/ /_/ / / / / / / /_/ / /  __/ /_/  __/
\____/\____/_/ /_/ /_/ .___/_/\___/\__/\___/ 
                    /_/                      

EOF
log "✅ Setup for '$instanceName' completed successfully."
ok  "✅ Setup for '$instanceName' completed successfully."
ui  "Log saved to: $logFile"
ok  "Access your Foundry instance at: https://$instanceUrl"
ui  ""
warn "To create another instance on this server, run this script again:"
ui  "./foundry-install.sh"
exit 0
