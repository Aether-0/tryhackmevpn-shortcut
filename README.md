## Made With Love By Zaw Wanz
---

# TryHackMe VPN Shortcut Maker

## Description
The TryHackMe VPN Shortcut Maker script automates the process of setting up a shortcut for the TryHackMe VPN connection on your system. It prompts the user to provide the path to the VPN configuration file and then installs the necessary files to create a shortcut for starting the VPN connection easily.

## Prerequisites
- This script requires root privileges to execute. Make sure to run it with `sudo`.

## Installation
1. Download the `thm and install.sh` script from this repository.
2. link:`https://github.com/ZawwanZ/tryhackmevpn-shortcut.git`
3. Make sure the script is executable by running:
   ```bash
   chmod +x *
   ```
4. Run the script with `sudo` to install the VPN shortcut:
   ```bash
   sudo ./install.sh
   ```
5. ## Enjoy
## Usage
After successful installation, you can use the following command to start the TryHackMe VPN connection:
```bash
thm -s
```
To stop the VPN connection, use:
```bash
thm -S
```

## Notes
- Make sure to provide the correct path to your VPN configuration file when prompted.
- The VPN configuration file will be moved to `/opt/thmvpn.ovpn` and the script will be moved to `/usr/bin/thm` for global access.
- The script checks if the installation is successful and provides appropriate feedback.

---
