#!/bin/bash

# Function to check and install packages
check_and_install_package() {
    local package_name=$1
    if [ -z "$package_name" ]; then
        package_name="xdg-utils"
    fi

    if ! command -v "$package_name" &> /dev/null; then
        echo "Error: $package_name command not found. Attempting to install $package_name."
        sudo apt install "$package_name" -y
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install $package_name. Please install it manually."
            exit 1
        fi
    fi
}

# Function to display usage information
usage() {
    echo "Usage: $0 [-v VPN_FILE_PATH] [-h]"
    echo "Options:"
    echo "  -v <VPN_FILE_PATH>  Specify the path to the VPN configuration file."
    echo "  -h                   Display this help message."
}

# Function to install only VPN file
new_vpn() {
    read -p "Enter the path to your new VPN file: " newvpn
    if [ ! -f "$newvpn" ]; then
        echo "Error: The specified file does not exist."
        exit 1
    fi
    
    sudo cp "$newvpn" /opt/thmvpn.ovpn
    if [ $? -eq 0 ]; then
        echo "New VPN file installed successfully."
    else
        echo "Error: Failed to install new VPN file."
    fi
}

# Check if the script is being run as root
if [ "$(whoami)" != "root" ]; then
    echo "Warning: This installation requires root privileges. Please run this script with sudo."
    exit 1
fi

# Parse command-line options
while getopts ":v:hn" opt; do
    case ${opt} in
        v )
            vpnfile=$OPTARG
            ;;
        h )
            usage
            exit 0
            ;;
        n )
            new_vpn
            exit 0  # Exit after installing the new VPN file
            ;;
        \? )
            echo "Error: Invalid option -$OPTARG" >&2
            usage
            exit 1
            ;;
        : )
            echo "Error: Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Check if VPN file path is provided
if [ -z "$vpnfile" ]; then
    echo "Error: VPN file path is required. Use -v option to specify the path."
    usage
    exit 1
fi

# Check if the provided file exists
if [ ! -f "$vpnfile" ]; then
    echo "Error: The specified VPN file does not exist."
    exit 1
fi

# Check and install required packages
check_and_install_package "curl"
check_and_install_package "openvpn"
check_and_install_package "xdg-open"

# Copy the VPN configuration file to /opt
sudo cp "$vpnfile" /opt/thmvpn.ovpn
# Define the name of the main script
main="thm"

# Move the main script to /usr/bin for global access
sudo cp "$main" /usr/bin/

# Make the main script executable
sudo chmod +x "/usr/bin/$main"

# Check if the main script is installed
if command -v "$main" &> /dev/null; then
    echo "Installation completed successfully."
    echo "You can run $main everywhere."
else
    echo "Failed to install $main. Please check if it's in your PATH."
fi
