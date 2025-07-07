#!/bin/bash
# Foundry VTT Automated Installer with Multi-Instance Support and elFinder WebUI File/Folder Access
# Author: TripodGG
# Version: 3.3



# ---- Configuration ---- #
scriptVersion="3.3"
currentUser=$(whoami)
homeDir=$(eval echo ~)
logFile='/foundry_instances/FoundryInstall.log'
red='\033[0;31m'
yellow='\033[33m'
green='\033[0;32m'
clear='\033[0m'

if [ "$EUID" -eq 0 ]; then
  echo ${red}"This script must NOT be run as root."${clear}
  exit 1
fi

# ---- Functions ---- #

  # -- Logging function -- #
log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local targetLog="$logFile"

    echo "[$timestamp] $message" | sudo tee -a "$targetLog" > /dev/null
}

  # -- Yes/no prompt --#
prompt_yes_no() {
    local prompt="$1"
    local var_name="$2"
    local result

    read -p "$prompt (y/n) [n]: " result
    result="${result,,}"  # lowercase

    if [[ -z "$result" || "$result" =~ ^n|no$ ]]; then
        eval "$var_name=false"
    elif [[ "$result" =~ ^y|yes$ ]]; then
        eval "$var_name=true"
    else
        echo "Invalid input. Please answer 'y' or 'n'."
        prompt_yes_no "$prompt" "$var_name"
    fi
}


# ------ BEGIN INSTALL ------ #

# Create log directory and file
sudo mkdir /foundry_instances
sudo touch /foundry_instances/FoundryInstall.log

# Clear the screen
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
echo -e ${yellow}"Installing dependencies..."${clear}

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
    sudo mv /var/www/elFinder-2.1.64/php/connector.minimal.php-dist /var/www/elFinder-2.1.64/php/connector.minimal.php
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
	echo -e ${red}"❌ Instance name cannot be empty."${clear}
	echo -e ${red}"❌ An error has occured. Please check the log file for details. $tempLogFile"${clear}
	exit 1
fi

# Create the instance directories then migrate the temp logs to instance logs
log "Creating instance directories..."
echo -e ${yellow}"Creating instance directories..."${clear}
instanceDir="/foundry_instances/$instanceName"
#appDir="$instanceDir/$instanceName"
dataDir="/foundry_instances/foundrydata/$instanceName"
assetsDir="/foundry_instances/assets"
modulesDir="/foundry_instances/modules"
sudo mkdir -p "$instanceDir" "$dataDir" "$assetsDir" "$modulesDir"
echo -e ${green}"Instance directories created successfully."${clear}

log "Foundry Install Started"
log "Installer version: $scriptVersion"
log "Instance name: $instanceName"
log "Directories created: $instanceDir, $dataDir, $assetsDir, $modulesDir"
sudo chown -R www-data:www-data /foundry_instances

# Prompt for Foundry URL
read -p "Enter the Foundry VTT download URL: " foundryUrl

# Move to install directory
cd "$instanceDir" || { log "❌ Failed to enter $instanceDir"; echo -e ${red}"An error has occurred. Please check the log file for details. $logFile"${clear}; exit 1; }

# Download Foundry VTT
log "Downloading Foundry VTT..."
echo -e ${yellow}"Downloading Foundry VTT..."${clear}
filename=foundryvtt.zip
sudo wget -O $filename "$foundryUrl" 2>&1 | sudo tee -a "$logFile" > /dev/null || { log "❌ Download failed. Check the URL. Did it expire?"; echo ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}; exit 1; }
log "Download complete: $filename"
echo -e ${green}"Download complete."${clear}

# Unzip the FoundryVTT file
log "Unzipping $filename..."
sudo unzip "$filename" 2>&1 | sudo tee -a "$logFile" > /dev/null || {
	log "❌ Failed to unzip archive."
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
	exit 1
}
echo -e ${yellow}"Unzipping Foundry VTT to $instanceDir..."${clear}

# Ensure main.js is executable
sudo chmod 755 "$instanceDir/resources/app/main.js" 2>&1 | sudo tee -a "$logFile" > /dev/null
log "Ensured $instanceDir/resources/app/main.js is now executable."
echo -e ${green}"Foundry VTT install complete."${clear}

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
setsid node foundry.js & 
PID=$!
PGID=$(ps -o pgid= $PID | grep -o '[0-9]*')

sleep 3

if curl -s http://localhost:30000 | grep -q "expected-text"; then
	echo "✅ Foundry is up and responding"
else
	echo "❌ Foundry did not respond as expected"
fi

# Send Ctrl+C to the whole group (graceful shutdown)
sudo kill -SIGINT -$PGID

# ---- Configure elFinder ---- #
# Download the custom connector file
# Variables
GITHUB_RAW_URL="https://raw.githubusercontent.com/TripodGG/Foundry-Automated-Install/Multi-install-3.0/connector.minimal.php"
DEST_PATH="/var/www/elFinder-2.1.64/php/connector.minimal.php"
BACKUP_PATH="${DEST_PATH}.bak.$(date +%Y%m%d%H%M%S)"
TMP_FILE="$(mktemp)"
CONFIG_DIR="/var/www/elFinder-2.1.64/php"
OUTPUT_FILE="$CONFIG_DIR/roots.config.php"
INSTANCES_BASE="/foundry_instances"
TMP_FILE=$(mktemp)

# Download the file
echo "Downloading latest connector.minimal.php to temporary file..."
sudo wget -q -O "$TMP_FILE" "$GITHUB_RAW_URL"

if [ $? -ne 0 ]; then
    echo "Download failed!"
    sudo rm -f "$TMP_FILE"
    exit 1
fi

REMOTE_SHA256=$(sha256sum "$TMP_FILE" | awk '{print $1}')
echo "Remote file SHA256: $REMOTE_SHA256"

if [ -f "$DEST_PATH" ]; then
    LOCAL_SHA256=$(sha256sum "$DEST_PATH" | awk '{print $1}')
    echo "Local file SHA256:  $LOCAL_SHA256"
else
    echo "Local file does not exist."
    LOCAL_SHA256=""
fi

if [ "$REMOTE_SHA256" = "$LOCAL_SHA256" ]; then
    echo "✅ Local file is up to date. No replacement needed."
    sudo rm -f "$TMP_FILE"
    exit 0
fi

echo "❗ File differs. Backing up and replacing..."

if [ -f "$DEST_PATH" ]; then
    sudo cp "$DEST_PATH" "$BACKUP_PATH"
    echo "Backed up local file to $BACKUP_PATH"
fi

sudo mv "$TMP_FILE" "$DEST_PATH"
sudo chown www-data:www-data "$DEST_PATH"
sudo chmod 644 "$DEST_PATH"

echo "✅ File replaced successfully."

# Input check
if [ -z "$1" ]; then
    echo "Usage: $0 <instanceName>"
    exit 1
fi

instanceName="$1"
instancePath="$INSTANCES_BASE/$instanceName"

# Validate that the instance folder exists
if [ ! -d "$instancePath" ]; then
    echo "❌ Error: Directory '$instancePath' does not exist."
    exit 1
fi

# Ensure the config directory exists
sudo mkdir -p "$CONFIG_DIR"

# Create initial config file if it doesn't exist
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Creating new $OUTPUT_FILE"
    echo "<?php" > "$OUTPUT_FILE"
    echo "return array(" >> "$OUTPUT_FILE"

    # Add trash volume block
    cat <<'EOL' >> "$OUTPUT_FILE"
    array(
        'id'            => '1',
        'driver'        => 'Trash',
        'path'          => '../files/.trash/',
        'tmbURL'        => dirname($_SERVER['PHP_SELF']) . '/../files/.trash/.tmb/',
        'winHashFix'    => DIRECTORY_SEPARATOR !== '/',
        'uploadDeny'    => array('all'),
        'uploadAllow'   => array('all'),
        'uploadOrder'   => array('deny', 'allow'),
        'accessControl' => 'access'
    ),
EOL
fi

# Remove last line (the closing `);`)
sed '$d' "$OUTPUT_FILE" > "$TMP_FILE"

# Check if the instance path is already present
if grep -q "$instancePath" "$TMP_FILE"; then
    echo "⚠️ Instance '$instanceName' already exists in $OUTPUT_FILE. Skipping."
else
    echo "➕ Adding instance: $instancePath"
    cat <<EOL >> "$TMP_FILE"
    array(
        'driver'        => 'LocalFileSystem',
        'path'          => '$instancePath',
        'trashHash'     => 't1_Lw',
        'winHashFix'    => DIRECTORY_SEPARATOR !== '/',
        'uploadDeny'    => array('all'),
        'uploadAllow'   => array('all'),
        'uploadOrder'   => array('deny', 'allow'),
        'accessControl' => 'access'
    ),
EOL
fi

# Add back the closing );
echo ");" >> "$TMP_FILE"

# Replace the original file
mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"

# Change ownership to www-data user and group
chown www-data:www-data "$OUTPUT_FILE"

echo "✅ roots.config.php updated successfully at $OUTPUT_FILE with ownership www-data:www-data"

# ---- Write the Caddy file ---- #
# Gather info for the Caddy file
read -p "Enter the URL that will be used for this instance (e.g. gamename.example.com): " instanceUrl
read -p "Enter the port number to use for this instance (e.g. 30001, 30002, etc.): " instancePort
caddyFile="/etc/caddy/Caddyfile"
hostPort="29999"

log "Writing Caddy config for $instanceUrl on port $instancePort..."

caddyEntry="
# FoundryVTT instance: $instanceName
$instanceUrl {
	reverse_proxy localhost:$instancePort
	encode zstd gzip
}"

# Remove any data related to port 80 from Caddy file
if grep -q '^:80[[:space:]]*{' /etc/caddy/Caddyfile; then
	sudo sed -i '/^:80[[:space:]]*{/,/^[[:space:]]*}/d' /etc/caddy/Caddyfile
	log "Removed :80 block from Caddyfile."
else
	log "No :80 block found. Nothing to do."
fi

# Write data to Caddy file
if ! grep -q "$instanceUrl" /etc/caddy/Caddyfile; then
	echo -e "$caddyEntry" | sudo tee -a /etc/caddy/Caddyfile > /dev/null
	log "Caddyfile entry appended for $instanceUrl"
else
	log "Caddyfile already contains an entry for $instanceUrl. Skipping append."
fi

# Top-level check: if port 29999 already exists anywhere in Caddyfile, exit early
if grep -q "$hostPort" "$caddyFile"; then
    echo ${yellow}"⚠️ Port $hostPort already configured in $caddyFile. No changes will be made."${clear}
    exit 0
fi

# If we reach here, port 29999 NOT found, proceed

# Prompt for elFinder host/domain
read -r -p "Enter the elFinder host/domain (e.g. your.domain.com): " elFinderhost
if [[ -z "$elFinderhost" ]]; then
    echo ${red}"❌ No host provided, exiting."${clear}
    exit 1
fi

# Get credentials securely
read -r -p "Enter a username for file manager: " USERNAME
read -r -s -p "Enter a password for file manager: " PASSWORD
echo ""

# Hash the password using Caddy's hash-password
HASH=$(caddy hash-password <<< "$PASSWORD")

# Append new reverse proxy block
echo "➕ Adding new reverse proxy block to $caddyFile..."

sudo tee -a "$caddyFile" > /dev/null <<EOF

$elFinderhost {
    reverse_proxy 127.0.0.1:29999

    basicauth {
        $USERNAME $HASH
    }
}
EOF

# Restart Caddy
sudo systemctl restart caddy 2>&1 | sudo tee -a "$logFile" > /dev/null
if [ $? -eq 0 ]; then
	log "✅ Caddy restarted successfully"
else
	log "❌ Caddy failed to restart"
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
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

if [ -f "$optionsFile" ]; then
	log "✅ options.json written successfully"
else
	log "❌ Failed to write options.json"
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
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
		echo -e ${red}"❌ Invalid input. Please enter a whole number (e.g. 2 or 2G)"${clear}
		echo -e ${red}"❌ An error has occured. Please check the log file for details. $logfile"${clear}
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

# ---- PM2 Setup ---- #
log "Setting up PM2..."

pm2Name="$instanceName"
startCommand="node $instanceDir/resources/app/main.js --dataPath=$dataDir"

log "Starting PM2 setup process: $pm2Name"
pm2 start "$startCommand" --name "$pm2Name" --watch 2>&1 | sudo tee -a "$logFile" > /dev/null
if [ $? -eq 0 ]; then
	log "✅ PM2 process '$pm2Name' started"
else
	log "❌ Failed to start PM2 process '$pm2Name'"
	echo -e ${red}"❌ An error occurred. Please check the log file for details: $logFile"${clear}
	exit 1
fi

log "Saving PM2 configuration..."
pm2 save 2>&1 | sudo tee -a "$logFile" > /dev/null
if [ $? -eq 0 ]; then
	log "✅ PM2 configuration saved"
else
	log "❌ Failed to save PM2 configuration"
	echo -e ${red}"❌ An error occurred. Please check the log file for details: $logFile"${clear}
	exit 1
fi

# ---- Finish script and close ---- #
sudo systemctl start apache2
log "✅ Setup for '$instanceName' completed successfully."
echo -e ${green}"Log saved to: $logFile"${clear}
echo ""
echo -e ${yellow}"To create another instance on this server, run this script again using:"${clear}
echo "./foundry-install.sh"
exit 0
