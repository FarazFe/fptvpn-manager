# fptvpn-manager

🌐 Languages: [English](README.md) | [فارسی](README_fa.md)

`fptvpn-manager` is a small, menu-based CLI tool for installing and managing  
**FPTN VPN Server** (`fptnvpn/fptn-vpn-server`) using Docker.

The goal of this project is simple:  
make it easy to deploy and operate an FPTN VPN server without manually dealing
with Docker commands, compose files, or configuration details.

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
curl -fsSL https://raw.githubusercontent.com/FarazFe/fptvpn-manager/main/fptvpn-manager.sh \
  -o /tmp/fptvpn-manager && sudo bash /tmp/fptvpn-manager
```

After this finishes, the `fptvpn-manager` command will be available system-wide.

---

## 🧭 Usage

Run the manager with:

```bash
sudo fptvpn-manager
```

You’ll get an interactive menu like this:

```
FPTVPN Manager
============================
Install dir: /opt/fptn

1) Easy install (creates a NEW user each run + token)
2) Custom install (configure + user + token)
3) Start service
4) Stop service
5) Show status
6) View logs
7) Update (pull latest image)
8) SSL: Generate certs (if missing)
9) SSL: Show MD5 fingerprint
10) Add VPN user (prints token)
11) Generate token (existing user / reset password)
0) Exit
```

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
/etc/fptvpn/manager.conf
```

---

## 🔄 Managing the service

Start the service:
```bash
sudo fptvpn-manager
# choose: Start service
```

Stop the service:
```bash
sudo fptvpn-manager
# choose: Stop service
```

Check status:
```bash
sudo fptvpn-manager
# choose: Show status
```

View logs:
```bash
sudo fptvpn-manager
# choose: View logs
```

Update the server image:
```bash
sudo fptvpn-manager
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
