from flask import Flask, request, render_template_string, send_file, abort
import os
import subprocess

app = Flask(__name__)

WG_CONFIG = "/etc/wireguard/wg0.conf"
PUBLIC_KEY_FILE = "/etc/wireguard/publickey"

# خواندن کلید عمومی سرور
try:
    SERVER_PUB_KEY = open(PUBLIC_KEY_FILE).read().strip()
except FileNotFoundError:
    SERVER_PUB_KEY = None

SERVER_ENDPOINT = None
DNS1 = "10.202.10.10"
DNS2 = "10.202.10.11"

def get_server_ip():
    # استخراج IP از فایل کانفیگ WireGuard (یا fallback)
    try:
        with open(WG_CONFIG, "r") as f:
            for line in f:
                if line.strip().startswith("ListenPort"):
                    port = line.strip().split('=')[1].strip()
                if line.strip().startswith("Address"):
                    ip = line.strip().split('=')[1].split('/')[0].strip()
        return f"{ip}:51820"
    except Exception:
        # fallback به آی‌پی لوکال
        return "YOUR_SERVER_IP:51820"

SERVER_ENDPOINT = get_server_ip()

def get_clients():
    clients = []
    for f in os.listdir('/etc/wireguard'):
        if f.startswith('client-') and f.endswith('.conf'):
            clients.append(f.replace('client-', '').replace('.conf', ''))
    return clients

@app.route('/')
def index():
    clients = get_clients()
    return render_template_string("""
    <h1>PEASY-WG WireGuard Panel</h1>
    <h3>Add New Client</h3>
    <form method="post" action="/add_client">
        <input type="text" name="client_name" required placeholder="Client name">
        <input type="submit" value="Create">
    </form>
    <h3>Existing Clients</h3>
    <ul>
        {% for client in clients %}
        <li>{{ client }} - <a href="/disable_client/{{ client }}" onclick="return confirm('Are you sure you want to disable this client?')">Disable</a></li>
        {% else %}
        <li>No clients found.</li>
        {% endfor %}
    </ul>
    """, clients=clients)

@app.route('/add_client', methods=['POST'])
def add_client():
    client_name = request.form['client_name'].strip()
    if not client_name.isalnum():
        return "Client name must be alphanumeric.", 400

    clients = get_clients()
    # محاسبه IP کلاینت جدید
    client_ip = f"10.202.10.{len(clients) + 2}/32"

    # تولید کلید کلاینت
    client_private_key = subprocess.check_output("wg genkey", shell=True).decode().strip()
    client_public_key = subprocess.check_output(f"echo '{client_private_key}' | wg pubkey", shell=True).decode().strip()

    client_config_path = f"/etc/wireguard/client-{client_name}.conf"

    # ساخت کانفیگ کلاینت
    client_config_content = f"""[Interface]
PrivateKey = {client_private_key}
Address = {client_ip}
DNS = {DNS1},{DNS2}

[Peer]
PublicKey = {SERVER_PUB_KEY}
Endpoint = {SERVER_ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""

    with open(client_config_path, "w") as f:
        f.write(client_config_content)

    # اضافه کردن کلاینت به کانفیگ سرور
    with open(WG_CONFIG, "a") as f:
        f.write(f"\n[Peer]\nPublicKey = {client_public_key}\nAllowedIPs = {client_ip}\n")

    # ری‌استارت WireGuard
    subprocess.run("systemctl restart wg-quick@wg0", shell=True)

    return send_file(client_config_path, as_attachment=True)

@app.route('/disable_client/<client_name>')
def disable_client(client_name):
    client_config = f"/etc/wireguard/client-{client_name}.conf"

    if not os.path.exists(client_config):
        return "Client config not found.", 404

    # حذف کلاینت از فایل سرور با دقت بیشتر
    with open(WG_CONFIG, "r") as f:
        lines = f.readlines()

    new_lines = []
    skip = False
    for line in lines:
        if line.strip() == "[Peer]":
            # ممکنه یک کلاینت شروع بشه
            skip = False
            # اگر این بلاک مربوط به کلاینت مورد نظر است، skip شود
            # جستجو در خطوط بعدی برای public key کلاینت
            idx = lines.index(line)
            if idx + 1 < len(lines) and client_name in lines[idx + 1]:
                skip = True

        if skip:
            continue
        new_lines.append(line)

    # بازنویسی فایل کانفیگ سرور
    with open(WG_CONFIG, "w") as f:
        f.writelines(new_lines)

    # حذف فایل کلاینت
    os.remove(client_config)

    # ری‌استارت WireGuard
    subprocess.run("systemctl restart wg-quick@wg0", shell=True)

    return f"Client {client_name} disabled and config removed."

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
