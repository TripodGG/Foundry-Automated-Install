#!/bin/bash
# Foundry VTT w/ FileGator Install Functions
# Author: TripodGG
# Version: 2.0



# ---- Install Configuration ---- #
scriptVersion="2.0"
tempLogFile="/tmp/foundry_install_temp.log"
currentUser=$(whoami)
homeDir=$(eval echo ~)
sharedDataDir="/var/www/filegator/repository/$instanceName/"
red='\033[0;31m'
yellow='\033[33m'
green='\033[0;32m'
clear='\033[0m'


# ---- Functions ---- #
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


log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local targetLog="${logFile:-$tempLogFile}"
    echo "[$timestamp] $message" | tee -a "$targetLog"
}


updatePackages() {
	# Update packages
	log "Updating system packages..." >> "$tempLogFile" 2>&1

	sudo apt update && sudo apt upgrade -y >> "$tempLogFile" 2>&1
	sudo mkdir -p /etc/apt/keyrings >> "$tempLogFile" 2>&1
	sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl >> "$tempLogFile" 2>&1
	if [ ! -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg ]; then
		curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg >> "$tempLogFile" 2>&1
		log "Caddy GPG key added"
	else
		log "Caddy GPG key already exists, skipping"
	fi
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >> "$tempLogFile" 2>&1
	curl -sL https://deb.nodesource.com/setup_20.x | sudo bash - >> "$tempLogFile" 2>&1
	sudo apt install -y ca-certificates curl gnupg unzip npm libssl-dev nodejs caddy >> "$tempLogFile" 2>&1
}


installApps() {
	# Install Packages
	log "Installing dependencies..." >> "$tempLogFile" 2>&1
	echo -e ${yellow}"Installing dependencies..."${clear}

	sudo apt install unzip libssl-dev nodejs apache2 git php composer caddy -y >> "$tempLogFile" 2>&1
	sudo npm install pm2 -g >> "$tempLogFile" 2>&1
}


installFilegator() {
	cd /var/www/
	git clone https://github.com/filegator/filegator.git
	cd filegator
	cp configuration_sample.php configuration.php
	chmod -R 775 private/
	chmod -R 775 repository/
	composer install --ignore-platform-reqs
	npm install
	npm run build
	npm run serve
}


modifyApache() {
	apacheCurrentUser=$(whoami)
	sudo groupadd foundry
	sudo usermod -aG foundry www-data
	sudo usermod -aG foundry $apacheCurrentUser
	sudo chown -R www-data:foundry /var/www/filegator/
	sudo sed -i 's/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=foundry/' /etc/apache2/envvars
	sudo sed -i 's/^Listen 80/Listen 29999/' /etc/apache2/ports.conf
	sudo echo "
		<VirtualHost *:29999>
			DocumentRoot /var/www/filegator/dist
		</VirtualHost>
		" >> /etc/apache2/sites-available/filegator.conf

	sudo a2dissite *
	sudo a2ensite filegator.conf
	sudo systemctl restart apache2
}


foundryInstall() {
	# Prompt for the instance name
	read -p "Enter a unique name for this instance (e.g., campaign1): " instanceName

	if [[ -z "$instanceName" ]]; then
		echo -e ${red}"❌ Instance name cannot be empty."${clear}
		echo -e ${red}"❌ An error has occured. Please check the log file for details. $tempLogFile"${clear}
		exit 1
	fi

	# Create the instance directories
	log "Creating instance directories..." >> "$tempLogFile" 2>&1
	echo -e ${yellow}"Creating instance directories..."${clear}

	instanceDir="$homeDir/$instanceName"
	appDir="$instanceDir/foundryvtt"
	dataDir="$instanceDir/data"
	logDir="$instanceDir/log"
	logFile="$logDir/install.log"
	mkdir -p "$appDir" "$dataDir" "$logDir"

	# Migrate the temp log file to the instance log file
	if [ -f "$tempLogFile" ]; then
		cat "$tempLogFile" >> "$logFile"
		rm "$tempLogFile"
		log "Migrated logs from temporary file"
	fi

	log "Foundry Multi-Instance Install Started"
	log "Installer version: $scriptVersion"
	log "Instance name: $instanceName"
	log "Directories created: $appDir, $dataDir, $logDir"

	# Prompt for Foundry URL
	read -p "Enter the Foundry VTT download URL: " foundryUrl

	# Move to install directory
	cd "$appDir" || { log "❌ Failed to enter $appDir"; echo -e ${red}"An error has occurred. Please check the log file for details. $logFile"${clear}; exit 1; }

	# Download Foundry VTT
	log "Downloading Foundry..."
	filename=foundryvtt.zip
	wget -O $filename "$foundryUrl" >> "$logFile" 2>&1 || { log "❌ Download failed. Check the URL. Did it expire?"; echo "❌ An error has occurred. Please check the log file for details. $logFile"; exit 1; }
	log "Download complete: $filename"

	# Unzip the FoundryVTT file
	log "Unzipping $filename..."
	unzip "$filename" >> "$logFile" 2>&1 || {
		log "❌ Failed to unzip archive."
		echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
		exit 1
	}

	# Ensure main.js is executable
	sudo chmod 755 "$appDir/resources/app/main.js" >> "$logFile" 2>&1
	log "Ensured $appDir/resources/app/main.js is now executable."

	# Prompt to delete the zip file
	prompt_yes_no "Delete the Foundry ZIP file to save space?" deleteZip
	if [ "$deleteZip" = true ]; then
		rm "$filename"
		log "$filename deleted"
	else
		log "$filename retained"
	fi
}

foundryStartupTest() {
	# Foundry startup test
	node resources/app/main.js --dataPath="$dataDir" & 
	pid=$!

	# Wait for server to respond
	echo "Starting FoundryVTT and waiting for HTTP response..."
	log "Starting FoundryVTT and waiting for HTTP response..."
	log "Waiting for FoundryVTT to respond on http://localhost:30000..."
	foundryReady=false

	for i in {1..20}; do
		headers=$(curl -s -o /dev/null -D - http://localhost:30000 2>/dev/null)
		if [[ $? -eq 0 ]]; then
			if echo "$headers" | grep -iq '^Location: /license'; then
				log "✅ Foundry successfully started."
				foundryReady=true
				break
			fi
		fi
		sleep 1
	done

	if [ "$foundryReady" = true ]; then
		log "✅ Foundry startup test passed."
		echo -e ${green}"✅ Foundry startup test passed."${clear}
	else
		log "❌ Foundry did not successfully launch.  Failed to respond with its default landing page ('License Key Activation') as expected."
		echo ${red}"❌ An error occurred. Please check $logFile for details."${clear}
		# Clean up
		kill $pid 2>/dev/null
		wait $pid 2>/dev/null
		exit 1
	fi

	# Clean up
	kill $pid 2>/dev/null
	wait $pid 2>/dev/null
}


writeCaddyFile() {
# Create the Caddy config file
read -p "Enter the URL that will be used for this instance (e.g. gamename.example.com): " hostUrl
read -p "Enter the port number to use for this instance (e.g. 30001): " hostPort

log "Writing Caddy config for $hostUrl on port $hostPort..."

caddyEntry="
# FoundryVTT instance: $instanceName
$hostUrl {
    reverse_proxy localhost:$hostPort
    encode zstd gzip
}"

if grep -q '^:80[[:space:]]*{' /etc/caddy/Caddyfile; then
    sudo sed -i '/^:80[[:space:]]*{/,/^[[:space:]]*}/d' /etc/caddy/Caddyfile
    log "Removed :80 block from Caddyfile."
else
    log "No :80 block found. Nothing to do."
fi

if ! grep -q "$hostUrl" /etc/caddy/Caddyfile; then
    echo -e "$caddyEntry" | sudo tee -a /etc/caddy/Caddyfile > /dev/null
    log "Caddyfile entry appended for $hostUrl"
else
    log "Caddyfile already contains an entry for $hostUrl. Skipping append."
fi

sudo systemctl restart caddy >> "$logFile" 2>&1
if [ $? -eq 0 ]; then
    log "✅ Caddy restarted successfully"
else
    log "❌ Caddy failed to restart"
	echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
    exit 1
fi
}

writeOptions() {
	# Write options.json
	optionsFile="$dataDir/Config/options.json"
	mkdir -p "$dataDir/Config"
	log "Writing options.json..."

cat <<EOF > "$optionsFile"
{
  "dataPath": "$dataDir",
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

	if [ -f "$optionsFile" ]; then
		log "✅ options.json written successfully"
	else
		log "❌ Failed to write options.json"
		echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
		exit 1
	fi
}


sharedFiles() {
	# Shared data folder setup
	log "Checking for shared data directory..."
	echo -e ${yellow}"Checking for shared data directory..."${clear}

		# Ensure shared directory exists
		if [ ! -d "$sharedDataDir" ]; then
			log "Shared data directory not found. Creating at $sharedDataDir..."
			mkdir -p "$sharedDataDir" >> "$logFile" 2>&1
			mkdir -p "$sharedDataDir/assets" >> "$logFile" 2>&1
			mkdir -p "$sharedDataDir/modules" >> "$logFile" 2>&1
			mkdir -p "$sharedDataDir/systems" >> "$logFile" 2>&1
			mkdir -p "$sharedDataDir/worlds" >> "$logFile" 2>&1
			log "✅ Shared data directory created"
		else
			log "✅ Shared data directory already exists"
		fi

		# Remove instance-specific data directory if it exists
		if [ -e "$dataDir/Data" ]; then
			log "Removing existing instance data directory or symlink at: $dataDir/Data"
			rm -rf "$dataDir/Data" >> "$logFile" 2>&1
			log "✅ Instance-specific data directory removed"
		else
			log "No existing instance data directory to remove"
		fi

		# Create symlink to shared modules directory
		log "Creating symlink: $sharedDataDir → $dataDir/Data"
		ln -s "$dataDir/Data" "$sharedDataDir" >> "$logFile" 2>&1

		# Verify symlink
		if [ -L "$sharedDataDir" ]; then
			log "✅ Symlink created successfully"
		else
			log "❌ Failed to create symlink to shared data directory"
			echo -e ${red}"❌ An error has occurred. Please check the log file for details. $logFile"${clear}
			exit 1
		fi
}


pm2Setup() {
	# PM2 Setup
	log "Setting up PM2..."

	pm2Name="$instanceName"
	startCommand="node $appDir/resources/app/main.js --dataPath=$dataDir"

	log "Starting PM2 setup process: $pm2Name"
	pm2 start "$startCommand" --name "$pm2Name" --watch >> "$logFile" 2>&1
	if [ $? -eq 0 ]; then
		log "✅ PM2 process '$pm2Name' started"
	else
		log "❌ Failed to start PM2 process '$pm2Name'"
		echo -e ${red}"❌ An error occurred. Please check the log file for details: $logFile"${clear}
		exit 1
	fi

	log "Saving PM2 configuration..."
	pm2 save >> "$logFile" 2>&1
	if [ $? -eq 0 ]; then
		log "✅ PM2 configuration saved"
	else
		log "❌ Failed to save PM2 configuration"
		echo -e ${red}"❌ An error occurred. Please check the log file for details: $logFile"${clear}
		exit 1
	fi
}


makeSwap() {
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
}
