from flask import Flask, request, render_template_string, send_file, abort
import os
import subprocess
import re

app = Flask(__name__)

WG_CONFIG = "/etc/wireguard/wg0.conf"
SERVER_PUB_KEY = open("/etc/wireguard/publickey").read().strip()
SERVER_ENDPOINT = "YOUR_SERVER_IP:51820"  # IP سرور و پورت
DNS1 = "10.202.10.10"
DNS2 = "10.202.10.11"
WG_IP_BASE = "10.202.10."  # شبکه کلاینت‌ها

def run_cmd(cmd_list):
    result = subprocess.run(cmd_list, capture_output=True, text=True)
    if result.returncode != 0:
        raise Exception(f"Command {' '.join(cmd_list)} failed: {result.stderr}")
    return result.stdout.strip()

@app.route('/')
def index():
    clients = get_clients()
    return render_template_string("""
    <h1>WireGuard Management Panel</h1>
    <h2>Add New Client</h2>
    <form method="post" action="/add_client">
        <label>Client Name: <input type="text" name="client_name" pattern="[a-zA-Z0-9_-]{1,20}" required></label><br>
        <small>فقط حروف، اعداد، - و _ مجاز است (حداکثر ۲۰ کاراکتر)</small><br>
        <input type="submit" value="Create Config">
    </form>
    <h2>Existing Clients</h2>
    <ul>
    {% for client in clients %}
        <li>{{ client }} <a href="/disable_client/{{ client }}">Disable</a></li>
    {% else %}
        <li>هیچ کلاینتی وجود ندارد</li>
    {% endfor %}
    </ul>
    """, clients=clients)

def get_clients():
    clients = []
    if not os.path.isdir('/etc/wireguard'):
        return clients
    for f in os.listdir('/etc/wireguard'):
        if f.startswith('client-') and f.endswith('.conf'):
            clients.append(f[len('client-'):-len('.conf')])
    return clients

def get_used_ips():
    ips = set()
    if not os.path.isfile(WG_CONFIG):
        return ips
    with open(WG_CONFIG, 'r') as f:
        data = f.read()
    # پیداکردن IP ها داخل AllowedIPs
    ips.update(re.findall(r'AllowedIPs\s*=\s*([\d\.]+)/32', data))
    return ips

def get_next_ip():
    used = get_used_ips()
    for i in range(2, 255):
        candidate = WG_IP_BASE + str(i)
        if candidate not in used:
            return candidate
    raise Exception("IP address pool exhausted")

@app.route('/add_client', methods=['POST'])
def add_client():
    client_name = request.form['client_name'].strip()
    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,20}', client_name):
        return "نام کلاینت نامعتبر است.", 400
    
    if client_name in get_clients():
        return "کلاینت با این نام وجود دارد.", 400
    
    client_ip = get_next_ip() + "/32"

    # تولید کلیدها با اجرای امن
    try:
        client_private_key = run_cmd(["wg", "genkey"])
        client_public_key = run_cmd(["wg", "pubkey"], input=client_private_key)
    except Exception as e:
        return f"خطا در تولید کلید: {str(e)}", 500
    
    client_config_path = f"/etc/wireguard/client-{client_name}.conf"
    with open(client_config_path, 'w') as f:
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
    # اضافه کردن به فایل کانفیگ سرور
    with open(WG_CONFIG, 'a') as f:
        f.write(f"\n[Peer]\nPublicKey = {client_public_key}\nAllowedIPs = {client_ip}\n")
    
    # ری‌استارت WireGuard با اجرای امن
    try:
        run_cmd(["systemctl", "restart", "wg-quick@wg0"])
    except Exception as e:
        return f"خطا در راه‌اندازی مجدد WireGuard: {str(e)}", 500

    return send_file(client_config_path, as_attachment=True)

@app.route('/disable_client/<client_name>')
def disable_client(client_name):
    if client_name not in get_clients():
        return "کلاینت وجود ندارد", 404
    
    client_config_path = f"/etc/wireguard/client-{client_name}.conf"
    if os.path.isfile(client_config_path):
        os.remove(client_config_path)

    # حذف بخش مربوط به کلاینت از wg0.conf
    try:
        with open(WG_CONFIG, 'r') as f:
            lines = f.readlines()
        new_lines = []
        skip = False
        for line in lines:
            if line.strip() == "[Peer]":
                skip = False
                peer_block = []
            if skip:
                if line.strip() == "":
                    skip = False
                continue
            if line.strip() == "[Peer]":
                peer_block = [line]
                skip = True
                continue
            new_lines.append(line)
        # راه حل دقیق‌تر با جستجوی کلید عمومی کلاینت
    except Exception as e:
        return f"خطا در خواندن فایل کانفیگ سرور: {str(e)}", 500

    # بهتر است روش حذف بر اساس کلید عمومی کلاینت انجام شود
    return "عملیات حذف کلاینت نیازمند به‌روزرسانی دقیق‌تر است.", 501

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
