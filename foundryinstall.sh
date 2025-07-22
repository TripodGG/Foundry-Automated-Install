#!/bin/bash
# Foundry automated game server install
# Written by TripodGG
# This script is designed to automate the process of setting up a dedicated server for FoundryVTT on Ubuntu Linux
# Version 3.5




# Configuration
set -euo pipefail
IFS=$'\n\t'
scriptVersion="3.5"
currentUser=$(whoami)
homeDir=$(eval echo ~)
logFile="/tmp/foundryinstall/install_$(date +%Y%m%d_%H%M%S).log"
stateFile="/tmp/foundryinstall/state.foundryinstall"
VERBOSE=false
red='\033[0;31m'
yellow='\033[33m'
green='\033[0;32m'
undo='\033[0m'

# Functions
# Logging function
log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$logFile"
    if [ "$VERBOSE" = true ]; then
        echo "[$timestamp] $message"
    fi
}


# Yes/no prompt
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

# Cleanup function
cleanup() {
	log "⚠️ Installation interrupted or failed. Running cleanup..."

	# Example rollback steps:
	sudo systemctl stop apache2 || true
	sudo systemctl restart caddy || true
	log "Cleaned up background services."

	# Optionally delete partially created files/directories (dangerous if too aggressive)
	# sudo rm -rf "$instanceDir" "$dataDir"

	echo -e ${red}"⚠️ Installation interrupted. Check the log at $logFile"${undo}
	exit 1
}

# Trap INT (Ctrl+C), TERM (kill), and ERR (error if using set -e)
trap cleanup INT TERM ERR

# Check if step is already done
checkpoint_done() {
	grep -q "$1" "$stateFile"
}

# Mark a checkpoint
mark_checkpoint() {
	echo "$1" >> "$stateFile"
	log "✅ Checkpoint reached: $1"
}




# ----- Begin Install ----- #

# Create the log file
mkdir -p "$(dirname "$logFile")"

# Ensure script is not ran as root
if [ "$EUID" -eq 0 ]; then
  echo ${red}"This script must NOT be run as root."${undo}
  exit 1
fi

# Clear the screen and start the script
clear

# Get Instance Info
echo " "
cat <<'EOF'

   ____                  __           _   ______________
  / __/__  __ _____  ___/ /_____ __  | | / /_  __/_  __/
 / _// _ \/ // / _ \/ _  / __/ // /  | |/ / / /   / /   
/_/  \___/\_,_/_//_/\_,_/_/  \_, /   |___/ /_/   /_/    
        ____         __     /___/_                      
       /  _/__  ___ / /____ _/ / /__ ____               
      _/ // _ \(_-</ __/ _ `/ / / -_) __/               
     /___/_//_/___/\__/\_,_/_/_/\__/_/                  
                                                        


EOF
echo " "
echo "Welcome, $currentUser, to the Foundry VTT Multi-Instance Installer"
echo "----------------------------------------------"
echo "This installer will prompt you for basic information about your Foundry instance."
read -n 1 -p "Press any key to begin the initial setup process."
echo "Begining installation. Please wait..."
sleep 3



log "🚀 Starting FoundryVTT install script (v$scriptVersion) for user $currentUser"

# ---- Update the system packages ---- #
log "Updating system packages..."

# update packages
sudo apt update && sudo apt upgrade -y

# create keyrings directory & file for caddy
sudo mkdir -p /etc/apt/keyrings
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
# check for keyring file, create it if needed, skip if not
if [ ! -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg ]; then
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	log "Caddy GPG key added"
else
	log "Caddy GPG key already exists, skipping"
fi
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
curl -sL https://deb.nodesource.com/setup_20.x | sudo bash -

# ---- Install base applications ---- #
log "Installing dependencies..."
echo -e ${yellow}"Installing dependencies..."${undo}

sudo apt install ca-certificates curl gnupg unzip net-tools libssl-dev nodejs apache2 git php composer caddy -y
sudo npm install pm2 -g

# ---- Check for elFinder installation ---- #
echo "Checking for elFinder installation."
log "Checking for elFinder installation."
if [ ! -d "/var/www/elFinder-2.1.64" ]; then
    echo "elFinder not found. Installing..."
	log "elFinder not found. Installing..."

    # ---- Install elFinder ---- #
    # Grab the install from GitHub and unzip
	cd /var/www/
	sudo wget -O elFinder.zip https://github.com/Studio-42/elFinder/archive/refs/tags/2.1.64.zip
    sudo unzip elFinder.zip
    sudo rm elFinder.zip

    # Create the index file and take ownership of www directory
    sudo mv /var/www/elFinder-2.1.64/elfinder.html /var/www/elFinder-2.1.64/index.html
    sudo cp $homeDir/Foundry-Automated-Install/connector.minimal.php /var/www/elFinder-2.1.64/php/connector.minimal.php
	sudo cp $homeDir/Foundry-Automated-Install/roots.config.php /var/www/elFinder-2.1.64/php/roots.config.php
    sudo chown -R www-data:www-data /var/www/

    # Create the elFinder config
    sudo systemctl stop apache2
    sudo sed -i 's/^Listen 80/Listen 29999/' /etc/apache2/ports.conf
    echo '
<VirtualHost *:29999>
	DocumentRoot /var/www/elFinder-2.1.64
</VirtualHost>
' | sudo tee -a /etc/apache2/sites-available/elfinder.conf > /dev/null

    # Disable other sites, enable elFinder
    for site in /etc/apache2/sites-enabled/*.conf; do
        siteName=$(basename "$site")
        if [[ "$siteName" != "elfinder.conf" ]]; then
            sudo a2dissite "$siteName"
        fi
    done
    sudo a2ensite elfinder.conf

    echo "elFinder installation complete."
	log "elFinder installation complete."
else
    echo "elFinder already installed. Skipping installation."
	log "elFinder already installed. Skipping installation."
fi

# ---- Install Foundry ---- #
# Prompt for the instance name
read -p "Enter a unique name for this instance (e.g., campaign1): " instanceName

if [[ -z "$instanceName" ]]; then
	log "❌ Instance name cannot be empty."
	echo -e ${red}"❌ An error has occured. Please check the log file for details. $logFile"${undo}
	exit 1
fi

# Create the instance directories then give ownership to www-data
log "Creating instance directories..."
echo -e ${yellow}"Creating instance directories..."${undo}
instanceDir="/foundry_instances/$instanceName"
dataDir="/foundry_instances/foundrydata/$instanceName"
assetsDir="/foundry_instances/assets"
modulesDir="/foundry_instances/modules"
sudo mkdir -p "$instanceDir" "$dataDir" "$assetsDir" "$modulesDir"
echo -e ${green}"Instance directories created successfully."${undo}
sudo chown -R www-data:www-data /foundry_instances
log "Foundry Install Started"
log "Installer version: $scriptVersion"
log "Instance name: $instanceName"
log "Directories created: $instanceDir, $dataDir, $assetsDir, $modulesDir"

# Prompt for Foundry URL
read -p "Enter the Foundry VTT download URL: " foundryUrl

# Move to install directory
cd "$instanceDir" || { log "❌ Failed to enter $instanceDir"; echo -e ${red}"An error has occurred. Please check the log file for details. $logFile"${undo}; exit 1; }

# Download Foundry VTT
log "Downloading Foundry VTT..."
echo -e ${yellow}"Downloading Foundry VTT..."${undo}
filename=foundryvtt.zip
sudo wget -O $filename "$foundryUrl" 2>&1 | sudo tee -a "$logFile" > /dev/null || { log "❌ Download failed. Check the URL. Did it expire?"; echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}; exit 1; }
log "Download complete: $filename"
echo -e ${green}"Download complete."${undo}

# Unzip the FoundryVTT file
log "Unzipping $filename..."
sudo unzip "$filename" 2>&1 | sudo tee -a "$logFile" > /dev/null || {
	log "❌ Failed to unzip archive."
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}
	exit 1
}
echo -e ${yellow}"Unzipping Foundry VTT to $instanceDir..."${undo}
echo -e ${yellow}"This may take some time. Please wait..."${undo}

# Ensure main.js is executable
sudo chmod 755 "$instanceDir/resources/app/main.js" 2>&1 | sudo tee -a "$logFile" > /dev/null
log "Ensured $instanceDir/resources/app/main.js is now executable."
echo -e ${green}"Foundry VTT install complete."${undo}

# Prompt to delete the zip file
prompt_yes_no "Would you like to delete the Foundry ZIP file to save space?" deleteZip
if [ "$deleteZip" = true ]; then
	sudo rm "$filename"
	log "$filename deleted"
else
	log "$filename retained"
fi

# ---- Foundry Startup Test ---- #
# Start Foundry in a new process group (so we can ctrl+c the whole thing)


# ---- Write the Caddy file ---- #
caddyFile="/etc/caddy/Caddyfile"
hostPort="29999"

read -p "Enter the URL that will be used for this instance (e.g. gamename.example.com): " instanceUrl
read -p "Enter the port number to use for this instance (e.g. 30001, 30002, etc.): " instancePort

if ! [[ "$instancePort" =~ ^[0-9]+$ ]] || [ "$instancePort" -le 1024 ] || [ "$instancePort" -gt 65535 ]; then
  log "❌ Invalid port number: $instancePort. Port number must be between 1025-65535."
  echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}
  exit 1
fi

log "Clearing Caddyfile..."

# Remove legacy :80 block if present
if grep -q '^:80[[:space:]]*{' "$caddyFile"; then
	sudo sed -i '/^:80[[:space:]]*{/,/^[[:space:]]*}/d' "$caddyFile"
	log "Removed :80 block from Caddyfile."
else
	log "No :80 block found. Nothing to do."
fi

# Write the Foundry instance entry
log "Writing Caddy config for $instanceUrl on port $instancePort..."
caddyEntry="
# FoundryVTT instance: $instanceName
$instanceUrl {
	reverse_proxy localhost:$instancePort
	encode zstd gzip
}"
if ! grep -q "$instanceUrl" "$caddyFile"; then
	echo "$caddyEntry" | sudo tee -a "$caddyFile" > /dev/null
	log "Caddyfile entry appended for $instanceUrl"
else
	log "Caddyfile already contains an entry for $instanceUrl. Skipping append."
fi

# Check if elFinder port is already configured
log "Checking Caddyfile for host port # $hostPort..."
echo "Checking Caddyfile for host port # $hostPort..."

if grep -q "$hostPort" "$caddyFile"; then
	echo -e ${yellow}"⚠️ Port $hostPort already configured in $caddyFile. Skipping elFinder setup."${undo}
	log "⚠️ Port $hostPort already configured in $caddyFile. Skipping elFinder reverse proxy setup."
else
	# Prompt to ask if elFinder should be configured
	prompt_yes_no "Would you like to set up the file explorer webUI?" setupElFinder
	if [ "$setupElFinder" = true ]; then
		# Prompt for elFinder host/domain
		read -r -p "Enter the elFinder host/domain (e.g. your.domain.com): " elFinderhost
		if [[ -z "$elFinderhost" ]]; then
			log "❌ elFinder host/domain cannot be blank."
			echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}
			exit 1
		fi

		# Get credentials securely
		read -r -p "Enter a username for file manager: " USERNAME
		read -r -s -p "Enter a password for file manager: " PASSWORD
		echo ""

		# Hash password using Caddy
		HASH=$(caddy hash-password <<< "$PASSWORD")
		if [[ -z "$HASH" ]]; then
			log "❌ Failed to generate password hash with caddy hash-password."
			echo -e ${red}"❌ An error has occurred while hashing password. Please check the log file for details. $logFile"${undo}
			exit 1
		fi

		# Append reverse proxy block
		log "Appending reverse proxy block for $elFinderhost on port 29999..."
		sudo tee -a "$caddyFile" > /dev/null <<EOF

# elFinder reverse proxy for file manager
$elFinderhost {
    reverse_proxy 127.0.0.1:29999

    basicauth {
        $USERNAME $HASH
    }

    tls
}
EOF

		if [[ $? -eq 0 ]]; then
			log "✅ Successfully added reverse proxy block for $elFinderhost"
		else
			log "❌ Failed to append reverse proxy block to $caddyFile."
			echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}
			exit 1
		fi
	else
		log "User declined to set up elFinder. Skipping file explorer reverse proxy block."
	fi
fi

# Restart Caddy
log "Restarting Caddy service..."
if sudo systemctl restart caddy 2>&1 | sudo tee -a "$logFile" > /dev/null; then
	log "✅ Caddy restarted successfully"
else
	log "❌ Caddy failed to restart"
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}
	exit 1
fi

# ---- Write Options.json file ---- #
optionsFile="$dataDir/Config/options.json"
sudo mkdir -p "$dataDir/Config"
log "Writing options.json..."

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
	log "❌ Failed to write options.json. Check permissions."
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${undo}
	exit 1
fi

# ---- Make Swap file ---- #
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
read -p "Enter the size of the swapfile in GB (default is 2G, recommended: ${recommendedSwapSize}G), or press enter if this step has already been completed in a previous instance installation: " swapSizeInput

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
		echo -e ${red}"❌ Invalid input. Please enter a whole number (e.g. 2 or 2G)"${undo}
		echo -e ${red}"❌ An error has occured. Please check the log file for details. $logFile"${undo}
		exit 1
	fi
fi

swapSize="${swapSizeGB}G"
log "User selected swap size: $swapSize"

# Create swapfile
log "Creating $swapSize swapfile at /swapfile..."
sudo fallocate -l "$swapSize" /swapfile 2>&1 | sudo tee -a "$logFile" > /dev/null
sudo chmod 600 /swapfile 2>&1 | sudo tee -a "$logFile" > /dev/null
sudo mkswap /swapfile 2>&1 | sudo tee -a "$logFile" > /dev/null && log "Swapfile created and marked as swap space"

# Add to /etc/fstab if not already present
if ! grep -q "^/swapfile" /etc/fstab; then
	echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null
	log "Swapfile entry added to /etc/fstab"
else
	log "Swapfile entry already present in /etc/fstab"
fi

# Enable swap
log "Enabling swapfile..."
sudo swapon -a 2>&1 | sudo tee -a "$logFile" > /dev/null

# Confirm and log the results
log "Swap status:"
sudo swapon --show | tee -a "$logFile"

# ----- PM2 Setup ----- #

log "🔧 Preparing PM2 environment for www-data user..."
echo "🔧 Configuring PM2..."

pm2Dir="/var/www/.pm2"
ecosystemFile="$pm2Dir/ecosystem.config.js"

# Ensure the PM2 directory exists
if [ ! -d "$pm2Dir" ]; then
    sudo mkdir -p "$pm2Dir" || { echo "❌ Failed to create $pm2Dir"; log "❌ Failed to create $pm2Dir"; exit 1; }
    sudo chown www-data:www-data "$pm2Dir"
    log "Created $pm2Dir"
fi

# Define the new app block
appBlock="    {
      name: \"$instanceName\",
      script: \"$instanceDir/resources/app/main.js\",
      args: \"--dataPath=$dataDir\",
      interpreter: \"node\",
      env: {
        NODE_OPTIONS: \"--max-old-space-size=4096\"
      }
    }"

# Append or create the ecosystem config
if sudo test -f "$ecosystemFile"; then
    log "Appending instance to existing ecosystem.config.js"
    
    # Remove the last two lines (the closing array and module exports bracket)
    sudo sed -i '$d' "$ecosystemFile"
    sudo sed -i '$d' "$ecosystemFile"

    # Append the new instance block
    echo "," | sudo tee -a "$ecosystemFile" > /dev/null
    echo "$appBlock" | sudo tee -a "$ecosystemFile" > /dev/null
    echo "  ]" | sudo tee -a "$ecosystemFile" > /dev/null
    echo "};" | sudo tee -a "$ecosystemFile" > /dev/null
else
    log "Creating new ecosystem.config.js"
    {
      echo "module.exports = {"
      echo "  apps: ["
      echo "$appBlock"
      echo "  ]"
      echo "};"
    } | sudo tee "$ecosystemFile" > /dev/null || { echo "❌ Failed to write ecosystem file"; log "❌ Failed to write ecosystem file"; exit 1; }
fi

# Start PM2 as www-data
log "Starting PM2 process for $instanceName"
echo "Starting PM2 process for $instanceName"
sudo -u www-data pm2 start "$ecosystemFile" >> "$logFile" 2>&1 || { echo "❌ Failed to start PM2"; log "❌ Failed to start PM2"; exit 1; }

# Save PM2 state
log "Saving PM2 process list..."
echo "Saving PM2 process list..."
sudo -u www-data pm2 save --force >> "$logFile" 2>&1 || { echo "❌ Failed to save PM2 process list"; log "❌ Failed to save PM2 process list"; exit 1; }

log "✅ PM2 configuration for $instanceName written and saved."
echo -e ${green}"✅ PM2 configuration for $instanceName written and saved."${undo}

# Symlink to the global shared assets and modules folders and confirm www-data owns the folders
log "Creating symlink: $dataDir/Data/assets -> $assetsDir"
log "Creating symlink: $dataDir/Data/modules -> $modulesDir"
sudo mkdir "$dataDir/Data/assets"
sudo mkdir "$dataDir/Data/modules"
sudo ln -sfn "$assetsDir" "$dataDir/Data/assets"
sudo ln -sfn "$modulesDir" "$dataDir/Data/modules"
if [ -L "$dataDir/Data/assets" ] && [ -L "$dataDir/Data/modules" ]; then
	log "✅ Symlinks created successfully."
else
	log "❌ Failed to create one or more symlinks."
fi

# ---- Finish script and close ---- #
sudo systemctl start apache2
log "✅ Setup for '$instanceName' completed successfully."
echo -e ${green}"✅ Setup for '$instanceName' completed successfully."${undo}
echo "Log saved to: $logFile"
echo -e ${green}"Access your Foundry instance at: https://$instanceUrl$"${undo}
echo ""
echo -e ${yellow}"To create another instance on this server, run this script again using:"${undo}
echo "./foundry-install.sh"
exit 0