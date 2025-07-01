#!/bin/bash

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# بررسی دسترسی root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root${NC}"
   exit 1
fi

# دریافت IP سرور
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
REPO_URL="https://github.com/Hamedunn/PEASY-WG.git"
INSTALL_DIR="/opt/peasy-wg"

echo -e "${GREEN}Starting minimal PEASY-WG setup...${NC}"

# نصب پیش‌نیازها
apt update
apt install -y python3 python3-pip python3-venv git wireguard

# کلون پروژه
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR

# ساخت محیط venv و نصب Flask
python3 -m venv $INSTALL_DIR/venv
source $INSTALL_DIR/venv/bin/activate
pip install --no-cache-dir flask
deactivate

# تولید کلید سرور
mkdir -p /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

# ساخت فایل اولیه کانفیگ wg
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.202.10.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# فعال‌سازی IP forwarding
grep -qF "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# راه‌اندازی WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# ساخت سرویس پنل با اجرای Python داخل venv
cat > /etc/systemd/system/peasy-wg-panel.service <<EOF
[Unit]
Description=PEASY-WG Web Panel
After=network.target

[Service]
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/app.py
WorkingDirectory=$INSTALL_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی پنل
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable peasy-wg-panel
systemctl restart peasy-wg-panel

# پیام نهایی
echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "Access your WireGuard panel at: ${GREEN}http://$SERVER_IP:5000${NC}"
