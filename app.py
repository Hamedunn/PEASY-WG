from flask import Flask, request, render_template_string, send_file, abort
import os
import subprocess

app = Flask(__name__)

WG_CONFIG = "/etc/wireguard/wg0.conf"
SERVER_PUB_KEY = open("/etc/wireguard/publickey").read().strip()
SERVER_ENDPOINT = "YOUR_SERVER_IP:51820"  # بعد از نصب جایگزین میشه
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
    existing_clients = [f for f in os.listdir('/etc/wireguard') if f.startswith('client-') and f.endswith('.conf')]
    client_ip = f"10.202.10.{len(existing_clients) + 2}/32"
    
    client_private_key = subprocess.check_output("wg genkey", shell=True).decode().strip()
    client_public_key = subprocess.check_output(f"echo '{client_private_key}' | wg pubkey", shell=True).decode().strip()
    
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
    
    with open(WG_CONFIG, 'a') as f:
        f.write(f"\n[Peer]\nPublicKey = {client_public_key}\nAllowedIPs = {client_ip}\n")
    
    subprocess.run("systemctl restart wg-quick@wg0", shell=True)
    
    return send_file(client_config_path, as_attachment=True)

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
    try:
        os.remove(f"/etc/wireguard/client-{client_name}.conf")
    except FileNotFoundError:
        pass
    return "Client disabled."

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
