#!/bin/bash
# Foundry VTT Automated Installer with Multi-Instance Support and FileGator Folder Access
# Author: TripodGG
# Version: 3.1



# Configuration
if [ "$EUID" -eq 0 ]; then
  echo "This script must NOT be run as root."
  exit 1
fi
scriptVersion="3.1"
tempLogFile="/tmp/foundry_install_temp.log"
homeDir=$(eval echo ~)
currentUser=$(whoami)
red='\033[0;31m'
yellow='\033[33m'
green='\033[0;32m'
clear='\033[0m'
source ./functions.sh



# Clear the screen
clear

# Get Instance Info
echo " "
cat <<'EOF'

   ____                  __           _   ______________         
  / __/__  __ _____  ___/ /_____ __  | | / /_  __/_  __/         
 / _// _ \/ // / _ \/ _  / __/ // /  | |/ / / /   / /            
/_/  \___/\_,_/_//_/\_,_/_/  \_, /   |___/ /_/   /_/             
                            /___/                           

          ____         __       ____                             
         /  _/__  ___ / /____ _/ / /__ ____                      
        _/ // _ \(_-</ __/ _ `/ / / -_) __/                      
       /___/_//_/___/\__/\_,_/_/_/\__/_/                                            
                                                             

EOF
echo " "
echo "Welcome, $currentUser, to the Foundry VTT Multi-Instance Installer"
echo "----------------------------------------------"
echo "The installer will prompt you for basic information about your Foundry instance."
read -n 1 -p "Press any key to begin the initial setup process."
echo "Begining installation. Please wait..."


# Run functions from source file
updatePackages &
installApps &
installFilegator &
modifyApache &
foundryInstall &
foundryStartupTest &
writeCaddyFile &
writeOptions &
sharedFiles &
pm2Setup &
makeSwap



# Finish script and close
log "✅ Multi-instance setup for '$instanceName' completed successfully."
echo -e ${green}"Log saved to: $logFile"${clear}
echo ""
echo -e ${yellow}"To create another instance on this server, run this script again using:"${clear}
echo "./foundry-install.sh"
exit 0
