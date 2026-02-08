# fptn-manager

🌐 Languages: [English](README.md) | [فارسی](README_fa.md)

`fptn-manager` is a small, menu-based CLI tool for installing and managing  
**FPTN VPN Server** (`fptnvpn/fptn-vpn-server`) using Docker.

The goal of this project is simple:  
make it easy to deploy and operate an FPTN VPN server without manually dealing
with Docker commands, compose files, or configuration details.

---

## ⚙️ How FPTN works

FPTN is a Layer-3 VPN that tunnels raw IP traffic over a connection designed to look like normal HTTPS. On the client side, a TUN interface captures IPv4 and IPv6 packets and forwards them through a secure tunnel to the server. The server performs NAT and routes the traffic to the internet, while also supporting split tunneling so only selected domains or IP ranges are sent through the VPN.

Instead of using standard VPN protocols, FPTN serializes IP packets using Protocol Buffers and transports them over a custom TLS-based channel built on BoringSSL. The transport layer includes random padding to reduce traffic fingerprinting and operates independently from OpenVPN- or WireGuard-style designs.

A key focus of FPTN is resistance to blocking and deep packet inspection. The VPN connection is masqueraded as regular HTTPS traffic on TCP port 443. Legitimate clients are identified directly at the TLS level using a modified session identifier, without an obvious VPN negotiation phase. The client supports several camouflage techniques, including SNI spoofing, TLS handshake obfuscation, and a “reality mode” where the connection initially behaves like a real HTTPS session before switching to the VPN tunnel. If a connection does not match the expected TLS fingerprint, the server transparently proxies traffic to the requested SNI domain, making the server indistinguishable from a normal HTTPS website.

User authentication is handled after the secure channel is established, using a username and password. The server enforces per-user bandwidth limits, can block unwanted traffic such as BitTorrent, and exposes a REST API for authentication, management, and monitoring. Operational metrics can be exported to Prometheus, and the architecture supports clustering and external integrations. Client configuration can be distributed using a compact token format that bundles the required connection parameters.

For full protocol details and client implementations, see the upstream project:
https://github.com/batchar2/fptn

---

## 📦 Requirements

- A Linux VPS or server
- Root access (`sudo`)
- Supported distributions:
  - Ubuntu / Debian
  - Rocky / Alma / RHEL
  - Other systemd-based distros

Docker and Docker Compose v2 are installed automatically if they’re missing.

---

## 🚀 Installation

This is the recommended and supported installation method:

```bash
curl -fsSL https://raw.githubusercontent.com/FarazFe/fptn-manager/main/fptn-manager.sh \
  -o /tmp/fptn-manager && sudo bash /tmp/fptn-manager
```

After this finishes, the `fptn-manager` command will be available system-wide.

---

## 🧭 Usage

Run the manager with:

```bash
sudo fptn-manager
```

You’ll get an interactive menu like this:

<img width="1347" height="506" alt="image" src="https://github.com/user-attachments/assets/f1a8d6c4-3d8d-44e3-9639-82812cb30b80" />

---

## 🟢 Easy Install (recommended)

This is the best option if you just want a working server quickly.

What it does:

- Uses sensible default settings
- Detects your server’s public IP automatically
- Installs everything into `/opt/fptn`
- Starts the VPN server right away
- **Creates a brand-new VPN user every time you run it**
- Prompts you to set a password once
- Prints a ready-to-use client token

Because Easy install always creates a new user, you can run it multiple times
without breaking existing users or tokens.

---

## 📱 Clients (Android / Linux / Windows / macOS)

After installing the server, the manager will print a **TOKEN** starting with `fptn:`.  
Copy the entire token and paste it into the client app to connect.

### ✅ Android
- Google Play: https://play.google.com/store/apps/details?id=org.fptn.vpn

### 🖥 Windows / 🐧 Linux / 🍎 macOS
Download the official desktop clients from the upstream project releases:
- Upstream Releases: https://github.com/batchar2/fptn/releases

> Note: pick the correct build for your OS/CPU (x86_64 vs arm64).

---

## 👤 Users, passwords, and tokens

A few important details:

- Passwords are always set **inside the container** using `fptn-passwd`
- Tokens are generated only after you re-enter the same password
- This avoids password mismatches and authentication errors

### Resetting a user’s password

Use menu option:

```
11) Generate token (existing user / reset password)
```

If you choose to reset the password, the manager will:

1. Delete the user interactively (you’ll confirm the deletion)
2. Re-create the user
3. Ask you to set a new password
4. Generate a fresh token

This is the safest way to recover if a client reports a “wrong password” error.

---

## 📁 File layout

Default installation layout:

```
/opt/fptn/
├── docker-compose.yml
├── .env
└── fptn-server-data/
    ├── server.key
    └── server.crt
```

Manager configuration file:

```
/etc/fptn/manager.conf
```

---

## 🔄 Managing the service

Start the service:
```bash
sudo fptn-manager
# choose: Start service
```

Stop the service:
```bash
sudo fptn-manager
# choose: Stop service
```

Check status:
```bash
sudo fptn-manager
# choose: Show status
```

View logs:
```bash
sudo fptn-manager
# choose: View logs
```

Update the server image:
```bash
sudo fptn-manager
# choose: Update (pull latest image)
```

---

## 🔐 SSL certificates

- SSL certificates are generated automatically if missing
- They’re stored persistently under `/opt/fptn/fptn-server-data`
- You can view the MD5 fingerprint from the menu if you need it for client
  verification

---

## 🛠 Troubleshooting

Check Docker:
```bash
systemctl status docker
```

Check containers:
```bash
cd /opt/fptn
docker compose ps
```

View server logs directly:
```bash
cd /opt/fptn
docker compose logs -f fptn-server
```

If a client shows **“wrong password”**:
- Re-run option **11**
- Choose to reset the password
- Generate a new token and try again

---

## 📜 License

MIT License  
You’re free to use, modify, and redistribute this project.

---

## ❤️ Credits

- FPTN VPN Server: https://github.com/batchar2/fptn
