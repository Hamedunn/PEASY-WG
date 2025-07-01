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

echo -e "${GREEN}Starting minimal PEASY-WG setup...${NC}"

# به‌روزرسانی سیستم و نصب فقط پیش‌نیازها
apt update
apt install -y python3 python3-pip git wireguard

# نصب Flask (پنل تحت وب)
pip3 install --no-cache-dir flask

# تولید کلیدهای سرور WireGuard
mkdir -p /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

# فایل اولیه wg0.conf (خالی از Peerها)
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

# راه‌اندازی و فعال‌سازی سرویس WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# کلون مخزن و آماده‌سازی فایل‌های پنل
git clone $REPO_URL /opt/peasy-wg
chmod -R 700 /opt/peasy-wg

# ساخت سرویس systemd برای اجرای دائمی پنل
cat > /etc/systemd/system/peasy-wg-panel.service <<EOF
[Unit]
Description=PEASY-WG Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/peasy-wg/app.py
WorkingDirectory=/opt/peasy-wg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی پنل
systemctl daemon-reexec
systemctl enable peasy-wg-panel
systemctl start peasy-wg-panel

# پیام نهایی
echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "Access your WireGuard panel at: ${GREEN}http://$SERVER_IP:5000${NC}"
