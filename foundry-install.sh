#!/bin/bash
# Foundry automated game server install
# Written by TripodGG
# This script is designed to automate the process of setting up a dedicated server for FoundryVTT on Ubuntu Linux
# Version 1.0

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

# Update packages
sudo apt update -y && sudo apt upgrade -y

# Install dependencies and Node.js 20
sudo apt install -y ca-certificates curl gnupg
curl -sL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs caddy unzip nano libssl-dev

# Install and set up PM2
sudo npm install pm2 -g
pm2 startup

# Get the current user
currentUser=$(whoami)

# Prompt for username, default to current user
read -p "Enter your username [${currentUser}]: " username
username=${username:-$currentUser}

# Get user's home directory
homeDir=$(getent passwd "$username" | cut -d: -f6)

# Create application and user data directories
mkdir -p "$homeDir/foundryvtt"
mkdir -p "$homeDir/foundrydata"

# Prompt for Foundry VTT download URL
read -p "Copy and paste the Foundry VTT download URL: " foundryUrl

# Move to install directory
cd "$homeDir/foundryvtt" || { echo "Failed to enter foundryvtt directory."; exit 1; }

# Download Foundry VTT
echo "Downloading Foundry Virtual Tabletop..."
wget --content-disposition "$foundryUrl"
downloadStatus=$?

if [ $downloadStatus -ne 0 ]; then
    echo "Download failed using --content-disposition. Trying fallback..."

    filename=$(basename "$foundryUrl")
    wget -O "$filename" "$foundryUrl"
    if [ $? -ne 0 ]; then
        echo "Fallback download failed. Please check the URL and try again."
        exit 1
    fi
else
    filename=$(ls -t *.zip | head -n 1)
fi

echo "Download complete: $filename"

# Unzip the file
if ! unzip "$filename"; then
    echo "❌ Failed to unzip $filename. Aborting."
    exit 1
fi

# Prompt to delete the zip file
prompt_yes_no "Do you want to delete the Foundry zip file to save space?" deleteZip

if [ "$deleteZip" = true ]; then
    rm "$filename"
    echo "$filename deleted"
else
    echo "$filename not deleted"
fi

# Start Foundry manually for now
node foundry/resources/app/main.js --dataPath="$homeDir/foundrydata"

# Check if Foundry started successfully
if [ $? -ne 0 ]; then
    echo "❌ Foundry failed to start. Please check for errors above."
    exit 1
else
    echo "✅ Foundry started successfully!"
fi

# Final messages
echo ""
echo "🎉 Foundry VTT has been installed!"
echo "Access it by going to: http://<your-server-ip>:30000"
echo "Did the Foundry VTT license page come up? Use Ctrl+C to stop the server for now."
echo "PM2 and Caddy support coming soon..."
