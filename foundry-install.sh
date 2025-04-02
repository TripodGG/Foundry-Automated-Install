#!/bin/bash
# Foundry automated game server install
# Written by TripodGG
# This script is designed to automate the process of setting up a dedicated server for FoundryVTT on Ubuntu Linux




scriptVersion="2.0"

# Reusable yes/no prompt function
prompt_yes_no() {
    local prompt="$1"
    local var_name="$2"
    local result

    read -p "$prompt (y/n) [n]: " result
    result="${result,,}"  # convert to lowercase

    # Default to "no" if empty
    if [[ -z "$result" || "$result" =~ ^n|no$ ]]; then
        eval "$var_name=false"
    elif [[ "$result" =~ ^y|yes$ ]]; then
        eval "$var_name=true"
    else
        echo "Invalid input. Please answer 'y' or 'n'."
        prompt_yes_no "$prompt" "$var_name"
    fi
}

# Logging function
log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$logFile"
}

# Get the current user
currentUser=$(whoami)

# Prompt for username, default to current user
read -p "Enter your username [${currentUser}]: " username
username=${username:-$currentUser}

# Get user's home directory
homeDir=$(getent passwd "$username" | cut -d: -f6)

# Set the log file location
logFile="$homeDir/install.log"
startTime=$(date '+%Y/%m/%d %H:%M')
log "Installation started at $startTime"
log "Installer version: $scriptVersion"

# Update packages
log "Updating system packages..."

sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl >> "$logFile" 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg >> "$logFile" 2>&1
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >> "$logFile" 2>&1
curl -sL https://deb.nodesource.com/setup_20.x | sudo bash - >> "$logFile" 2>&1
sudo apt install -y ca-certificates curl gnupg >> "$logFile" 2>&1
sudo mkdir -p /etc/apt/keyrings >> "$logFile" 2>&1
sudo apt update && sudo apt upgrade -y >> "$logFile" 2>&1

# Install Packages
sudo apt install unzip -y >> "$logFile" 2>&1
sudo apt install npm -y >> "$logFile" 2>&1
sudo apt install libssl-dev -y >> "$logFile" 2>&1
sudo apt install nodejs -y >> "$logFile" 2>&1
sudo apt install caddy -y >> "$logFile" 2>&1
sudo npm install pm2 -g >> "$logFile" 2>&1

# Capture the PM2 startup command
startupCmd=$(pm2 startup | grep sudo)

# Run it automatically if found
if [ -n "$startupCmd" ]; then
    eval "$startupCmd" >> "$logFile" 2>&1 && log "PM2 startup command executed."
else
    log "⚠️ PM2 startup command could not be parsed or was not needed."
fi

# Create application and user data directories
log "Creating application directories..."
mkdir -p "$homeDir/foundryvtt" "$homeDir/foundrydata"
log "Directories created at $homeDir/foundryvtt and $homeDir/foundrydata"

# Prompt for Foundry VTT download URL
read -p "Copy and paste the Foundry VTT download URL: " foundryUrl

# Move to install directory
cd "$homeDir/foundryvtt" || { log "❌ Failed to enter foundryvtt directory."; exit 1; }

# Download Foundry VTT
log "Downloading Foundry Virtual Tabletop..."
filename=foundryvtt.zip
wget -O $filename "$foundryUrl" >> "$logFile" 2>&1
log "Download complete: $filename"

# Unzip the FoundryVTT file
log "Unzipping $filename..."
if ! unzip "$filename" >> "$logFile" 2>&1; then
    log "❌ Failed to unzip $filename. Aborting."
    exit 1
fi
log "Unzip successful"

# Ensure main.js is executable
log "Ensuring main.js is executable..."
sudo chmod 755 "$homeDir/foundryvtt/resources/app/main.js" >> "$logFile" 2>&1

# Prompt to delete the zip file
prompt_yes_no "Do you want to delete the Foundry zip file to save space?" deleteZip

if [ "$deleteZip" = true ]; then
    rm "$filename"
    log "$filename deleted"
else
    log "$filename not deleted"
fi

# Get private and public IP addresses
privateIp=$(hostname -I | awk '{print $1}')
publicIp=$(curl -s ifconfig.me)
log "Detected private IP: $privateIp"
log "Detected public IP: $publicIp"

# Start Foundry manually for now
echo "🎉 Foundry VTT has been installed!"
log "Starting Foundry..."
echo ""
echo "Please go to either http://$privateIp:30000 or http://$publicIp:30000 in your browser."
echo "This is to confirm Foundry VTT has successfully started for the first time."
echo "Press CTRL+C after you've verified you can see the Foundry VTT license page."
node resources/app/main.js --dataPath="foundrydata" >> "$logFile" 2>&1
echo ""

# Check if Foundry started successfully
if [ $? -ne 0 ]; then
    log "❌ Foundry failed to start. Please check for errors in the log file."
    exit 1
else
    log "✅ Foundry started successfully!"
fi

log "Access instructions: http://$privateIp:30000 or http://$publicIp:30000"

prompt_yes_no "Did the Foundry VTT license page come up?" licensePageLoaded

if [ "$licensePageLoaded" = true ]; then
    log "✅ User confirmed the Foundry license page loaded successfully."
else
    log "❌ User reported the Foundry license page did NOT load."
    log "Script stopping. Please check $logFile for errors and try again."
    echo ""
    echo "❌ Foundry VTT may not have started correctly."
    echo "Please check the log file at $logFile for details, resolve the issue, and re-run the script."
    exit 1
fi

# Set PM2 config
log "Creating PM2 configuration..."
startCommand="node resources/app/main.js --dataPath=foundrydata"
pm2 start "$startCommand" --name foundry --watch >> "$logFile" 2>&1 && log "PM2 process 'foundry' started with watch enabled"
pm2 save >> "$logFile" 2>&1 && log "PM2 configuration saved for Foundry startup"

# Prompt for the server URL and port number
read -p "Enter the URL that will be used for this server (e.g. foundry.yourdomain.com): " hostUrl
log "Received host URL: $hostUrl"

read -p "Enter the port that will be used for this server (e.g. 30000): " hostPort
log "Received host port: $hostPort"

# Write the Caddyfile
log "Writing Caddy configuration to /etc/caddy/Caddyfile..."
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
# FoundryVTT Caddy Reverse Proxy Configuration

$hostUrl {
    reverse_proxy localhost:$hostPort
    encode zstd gzip
}

https:// {
    tls internal {
        on_demand
    }

    reverse_proxy localhost:$hostPort
    encode zstd gzip
}

# Refer to the Caddy docs for more information:
# https://caddyserver.com/docs/caddyfile
EOF

log "Caddyfile written with host URL: $hostUrl"

# Restart Caddy
log "Restarting Caddy to apply configuration..."
sudo service caddy restart >> "$logFile" 2>&1

if [ $? -eq 0 ]; then
    log "✅ Caddy restarted successfully"
else
    log "❌ Failed to restart Caddy. Please check the log file and Caddyfile syntax."
    echo "❌ Caddy failed to restart. Check $logFile or run: sudo systemctl status caddy"
    exit 1
fi

# Set defaults for the options file
configDir="$homeDir/foundrydata/Config"
optionsFile="$configDir/options.json"
backupFile="$configDir/options.json.bak"

# Ensure the config directory exists
mkdir -p "$configDir"

# Backup existing options.json if it exists
if [ -f "$optionsFile" ]; then
    cp "$optionsFile" "$backupFile"
    log "📦 Existing options.json backed up to options.json.bak"
fi

# Write the new options.json file
log "Writing new options.json to $optionsFile..."

cat <<EOF > "$optionsFile"
{
  "dataPath": "$homeDir/foundrydata",
  "compressStatic": true,
  "fullscreen": false,
  "hostname": "$hostUrl",
  "language": "en.core",
  "localHostname": null,
  "port": $hostPort,
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

# Validate the file write
if [ -f "$optionsFile" ]; then
    log "✅ options.json written successfully"
else
    log "❌ Failed to write options.json. Attempting to restore from backup..."

    if [ -f "$backupFile" ]; then
        cp "$backupFile" "$optionsFile"
        log "✅ Restored original options.json from backup"
        echo "❌ New config failed. Restored previous config file."
    else
        log "❌ No backup available to restore."
        echo "❌ New config failed and no backup found. Please fix manually."
    fi

    exit 1
fi

# Restart Foundry to take the new config
sudo service caddy restart
pm2 restart foundry

# Detect system memory and recommend swap size
memTotalKB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
memTotalGB=$(( (memTotalKB + 1048575) / 1048576 ))  # Round up
log "System memory detected: ${memTotalGB}GB"

# Recommend swap size based on total memory
if [ "$memTotalGB" -lt 2 ]; then
    recommendedSwapSize=$((memTotalGB * 2))
elif [ "$memTotalGB" -le 4 ]; then
    recommendedSwapSize=$((memTotalGB + memTotalGB / 2))  # 1.5x
elif [ "$memTotalGB" -le 8 ]; then
    recommendedSwapSize=$memTotalGB
else
    recommendedSwapSize=2
fi

log "Recommended swap size: ${recommendedSwapSize}G"

# Prompt for swap size
read -p "Enter the size of the swapfile in GB (default is 2G, recommended: ${recommendedSwapSize}G): " swapSizeInput

# If input is blank, use default
if [ -z "$swapSizeInput" ]; then
    swapSizeGB=2
    log "No swap size entered. Defaulting to 2G"
else
    # Normalize input and remove unit
    swapSizeInput=$(echo "$swapSizeInput" | tr '[:lower:]' '[:upper:]')
    swapSizeGB=$(echo "$swapSizeInput" | sed 's/G[B]*$//')

    # Validate that it's numeric
    if ! [[ "$swapSizeGB" =~ ^[0-9]+$ ]]; then
        log "❌ Invalid swap size entered: $swapSizeInput"
        echo "❌ Invalid input. Please enter a whole number (e.g. 2 or 2G)"
        exit 1
    fi
fi

swapSize="${swapSizeGB}G"
log "User selected swap size: $swapSize"

# Create swapfile
log "Creating $swapSize swapfile at /swapfile..."
sudo fallocate -l "$swapSize" /swapfile >> "$logFile" 2>&1
sudo chmod 600 /swapfile >> "$logFile" 2>&1
sudo mkswap /swapfile >> "$logFile" 2>&1 && log "Swapfile created and marked as swap space"

# Add to /etc/fstab if not already present
if ! grep -q "^/swapfile" /etc/fstab; then
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null
    log "Swapfile entry added to /etc/fstab"
else
    log "Swapfile entry already present in /etc/fstab"
fi

# Enable swap
log "Enabling swapfile..."
sudo swapon -a >> "$logFile" 2>&1

# Confirm and log the results
log "Swap status:"
sudo swapon --show | tee -a "$logFile"

# Log the successful install
log "✅ Installation completed successfully at $(date '+%Y/%m/%d %H:%M')"
echo "📝 Log file saved to $logFile"
exit 0

