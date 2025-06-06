# PEASY-WG

[English](#english) | [فارسی](#فارسی)

---

## English

**PEASY-WG** is an automated script for installing and configuring **WireGuard VPN** on Ubuntu 22.04, featuring a simple web panel for client management and daily GitHub repository sync.

### Features
- Automatic WireGuard and dependencies installation.
- Server setup with DNS servers `10.202.10.10` and `10.202.10.11`.
- Client config generation with QR code.
- Flask-based web panel for client management.
- Daily GitHub repository synchronization.

### Prerequisites
- Ubuntu 22.04
- Root or sudo access
- Public IP and internet connection

### Installation
1. Download the script:
```bash
sudo apt update
wget https://raw.githubusercontent.com/Hamedunn/PEASY-WG/main/setup.sh
chmod +x setup.sh
