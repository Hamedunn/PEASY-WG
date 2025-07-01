#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root${NC}"
   exit 1
fi

SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
WG_PORT=51820

echo -e "${GREEN}Starting optimized WireGuard setup...${NC}"

# آزادسازی حافظه
sync; echo 3 | tee /proc/sys/vm/drop_caches

# ساخت Swap 1 گیگ اگر موجود نیست
if ! swapon --show | grep -q "/swapfile"; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# غیرفعال کردن appstreamcli
systemctl disable --now apt-appstream 2>/dev/null
rm -rf /var/cache/appstream

# به‌روزرسانی و نصب بسته‌های ضروری
apt update
apt install -y wireguard python3 python3-venv git ufw

# ساخت دایرکتوری پروژه
mkdir -p /opt/peasy-wg
cd /opt/peasy-wg

# کلون مخزن گیتهاب
git clone https://github.com/Hamedunn/PEASY-WG.git . || {
    echo -e "${RED}Git clone failed!${NC}"
    exit 1
}

# ساخت محیط مجازی پایتون و نصب Flask
python3 -m venv venv
source venv/bin/activate
pip install --no-cache-dir flask
deactivate

# تولید کلید WireGuard در صورت نبود
if [ ! -f /etc/wireguard/privatekey ]; then
    umask 077
    wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
fi

# پیکربندی WireGuard
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.202.10.1/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# فعال سازی IP Forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# فعال کردن WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# تنظیم فایروال
ufw allow $WG_PORT/udp
ufw allow 5000/tcp
ufw --force enable

# ساخت سرویس systemd برای پنل تحت وب
cat > /etc/systemd/system/peasy-wg-panel.service << EOF
[Unit]
Description=PEASY-WG Web Panel
After=network.target

[Service]
ExecStart=/opt/peasy-wg/venv/bin/python /opt/peasy-wg/app.py
WorkingDirectory=/opt/peasy-wg
Restart=always
MemoryLimit=100M

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable peasy-wg-panel
systemctl restart peasy-wg-panel

echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "Access your WireGuard panel at: http://${SERVER_IP}:5000"
