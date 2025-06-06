#!/bin/bash

# رنگ‌ها برای خروجی
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# بررسی دسترسی root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run as root${NC}"
   exit 1
fi

# دریافت IP سرور
SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
WG_PORT=51820
DNS1="10.202.10.10"
DNS2="10.202.10.11"
REPO_URL="https://github.com/Hamedunn/PEASY-WG.git"

echo -e "${GREEN}Starting optimized WireGuard setup...${NC}"

# آزادسازی حافظه
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches

# ایجاد Swap (1 گیگابایت)
if ! swapon --show | grep -q "/swapfile"; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# غیرفعال کردن appstreamcli برای کاهش مصرف حافظه
systemctl disable --now apt-appstream 2>/dev/null
rm -rf /var/cache/appstream

# به‌روزرسانی و نصب حداقل بسته‌ها
apt update
apt install -y wireguard python3 python3-pip git

# نصب Flask با حداقل وابستگی‌ها
pip3 install --no-cache-dir flask

# تولید کلیدهای WireGuard
umask 077
mkdir -p /etc/wireguard
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
SERVER_PUB_KEY=$(cat /etc/wireguard/publickey)

# پیکربندی WireGuard
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.202.10.1/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# فعال‌سازی IP Forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# راه‌اندازی WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# تنظیم فایروال
ufw allow $WG_PORT/udp
ufw allow 5000/tcp
ufw --force enable

# کلون مخزن
git clone $REPO_URL /opt/wireguard-auto-setup
cd /opt/wireguard-auto-setup

# اسکریپت تولید کانفیگ کلاینت (بدون QR کد برای صرفه‌جویی در حافظه)
cat > /usr/local/bin/add-wireguard-client.sh << 'EOF'
#!/bin/bash
WG_CONFIG="/etc/wireguard/wg0.conf"
SERVER_PUB_KEY=$(cat /etc/wireguard/publickey)
SERVER_ENDPOINT="YOUR_SERVER_IP:$WG_PORT"
DNS1="10.202.10.10"
DNS2="10.202.10.11"
CLIENT_IP="10.202.10.$(( $(grep -c AllowedIPs $WG_CONFIG) + 2 ))/32"

umask 077
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

CLIENT_CONFIG="/etc/wireguard/client-$CLIENT_PUBLIC_KEY.conf"
cat > $CLIENT_CONFIG << EOC
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP
DNS = $DNS1,$DNS2

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOC

echo -e "\n[Peer]\nPublicKey = $CLIENT_PUBLIC_KEY\nAllowedIPs = $CLIENT_IP" | tee -a $WG_CONFIG
systemctl restart wg-quick@wg0

echo "Client config created at $CLIENT_CONFIG:"
cat $CLIENT_CONFIG
EOF

sed -i "s/YOUR_SERVER_IP/$SERVER_IP/g" /usr/local/bin/add-wireguard-client.sh
chmod +x /usr/local/bin/add-wireguard-client.sh

# پنل تحت وب (بهینه‌شده)
cat > /opt/wireguard-auto-setup/app.py << 'EOF'
from flask import Flask, request, render_template_string, send_file
import os
import subprocess

app = Flask(__name__)
WG_CONFIG = "/etc/wireguard/wg0.conf"
SERVER_PUB_KEY = open("/etc/wireguard/publickey").read().strip()
SERVER_ENDPOINT = "SERVER_IP:51820"
DNS1 = "10.202.10.10"
DNS2 = "10.202.10.11"

@app.route('/')
def index():
    clients = [f.replace('client-', '').replace('.conf', '') for f in os.listdir('/etc/wireguard') if f.startswith('client-') and f.endswith('.conf')]
    return render_template_string("""
    <h1>WireGuard Panel</h1>
    <h3>Add Client</h3>
    <form method="post" action="/add_client">
        <input type="text" name="client_name" required>
        <input type="submit" value="Create">
    </form>
    <h3>Clients</h3>
    <ul>{% for client in clients %}<li>{{ client }} <a href="/disable_client/{{ client }}">Disable</a></li>{% endfor %}</ul>
    """, clients=clients)

@app.route('/add_client', methods=['POST'])
def add_client():
    client_name = request.form['client_name']
    client_ip = f"10.202.10.{len(os.listdir('/etc/wireguard')) + 2}/32"
    client_private_key = subprocess.check_output("wg genkey", shell=True).decode().strip()
    client_public_key = subprocess.check_output(f"echo '{client_private_key}' | wg pubkey", shell=True).decode().strip()
    client_config = f"/etc/wireguard/client-{client_name}.conf"
    with open(client_config, 'w') as f:
        f.write(f"""[Interface]
PrivateKey = {client_private_key}
Address = {client_ip}
DNS = {DNS1},{DNS2}

[Peer]
PublicKey = {SERVER_PUB_KEY}
Endpoint = {SERVER_ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
""")
    with open(WG_CONFIG, 'a') as f:
        f.write(f"\n[Peer]\nPublicKey = {client_public_key}\nAllowedIPs = {client_ip}\n")
    subprocess.run("systemctl restart wg-quick@wg0", shell=True)
    return send_file(client_config, as_attachment=True)

@app.route('/disable_client/<client_name>')
def disable_client(client_name):
    with open(WG_CONFIG, 'r') as f:
        lines = f.readlines()
    with open(WG_CONFIG, 'w') as f:
        skip = False
        for line in lines:
            if client_name in line:
                skip = True
            elif line.startswith('[Peer]') or line.strip() == '':
                skip = False
            if not skip:
                f.write(line)
    subprocess.run("systemctl restart wg-quick@wg0", shell=True)
    os.remove(f"/etc/wireguard/client-{client_name}.conf")
    return "Client disabled."

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, threaded=False)
EOF

sed -i "s/SERVER_IP/$SERVER_IP/g" /opt/wireguard-auto-setup/app.py

# سرویس پنل
cat > /etc/systemd/system/wireguard-panel.service << EOF
[Unit]
Description=WireGuard Panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/wireguard-auto-setup/app.py
WorkingDirectory=/opt/wireguard-auto-setup
Restart=always
MemoryLimit=100M

[Install]
WantedBy=multi-user.target
EOF

systemctl enable wireguard-panel
systemctl start wireguard-panel

# همگام‌سازی
cat > /opt/wireguard-auto-setup/sync.sh << 'EOF'
#!/bin/bash
cd /opt/wireguard-auto-setup
git pull origin main
systemctl restart wireguard-panel
EOF
chmod +x /opt/wireguard-auto-setup/sync.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/wireguard-auto-setup/sync.sh") | crontab -

echo -e "${GREEN}Setup done!${NC}"
echo -e "Web panel: ${GREEN}http://$SERVER_IP:5000${NC}"
echo -e "Add client: ${GREEN}sudo /usr/local/bin/add-wireguard-client.sh${NC}"
