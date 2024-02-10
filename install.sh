#!/bin/bash

# Check if the script is being run as root
if [ "$(whoami)" != "root" ]; then
    echo "Warning: This installation requires root privileges. Please run this script with sudo."
    exit 1
fi

# Prompt the user to enter the VPN file path
read -p "Enter your VPN file path: " vpnfile

# Copy the VPN configuration file to /opt
sudo cp "$vpnfile" /opt/thmvpn.ovpn

# Remove the original VPN file
rm -f "$vpnfile"

# Define the name of the main script
main="thm"

# Move the main script to /usr/bin for global access
sudo mv "$main" /usr/bin/

# Make the main script executable
sudo chmod +x "/usr/bin/$main"

# Check if the main script is installed
if command -v "$main" &> /dev/null; then
    echo "Installation completed successfully."
else
    echo "Failed to install $main. Please check if it's in your PATH."
fi
