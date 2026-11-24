
#!/bin/bash

# ==========================================================
# CYBERTRACE - NMAP TRAINING LAB
# Debian 13 | Lightweight Service Enumeration Target
# ==========================================================

set -Eeuo pipefail

# ---------------- CONFIGURATION ----------------

LAB_USER="labuser"
LAB_PASSWORD="LabOnly-2026!"

FTP_DIR="/srv/ftp"
SMB_DIR="/srv/samba/public"
WEB_DIR="/var/www/html"

DB_NAME="labdb"
DB_USER="nmapuser"
DB_PASSWORD="NmapDB-2026!"

# ------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "[!] Run this script as root:"
    echo "    sudo bash setup-nmap-lab.sh"
    exit 1
fi

echo ""
echo "=============================================="
echo "       CYBERTRACE NMAP TRAINING LAB"
echo "=============================================="
echo ""

# ------------------------------------------------
# 1. INSTALL PACKAGES
# ------------------------------------------------

echo "[1/8] Updating package repositories..."

apt-get update

echo "[+] Installing required services..."

export DEBIAN_FRONTEND=noninteractive

apt-get install -y \
    openssh-server \
    vsftpd \
    nginx \
    samba \
    mariadb-server \
    mariadb-client \
    openbsd-inetd \
    inetutils-telnetd \
    net-tools \
    curl \
    iproute2

# ------------------------------------------------
# 2. CREATE LAB USER
# ------------------------------------------------

echo "[2/8] Creating training user..."

if ! id "$LAB_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$LAB_USER"
fi

echo "${LAB_USER}:${LAB_PASSWORD}" | chpasswd

# ------------------------------------------------
# 3. CONFIGURE FTP - PORT 21
# ------------------------------------------------

echo "[3/8] Configuring FTP..."

mkdir -p "$FTP_DIR/pub"

cat > "$FTP_DIR/README.txt" <<'EOF'
=================================
 CYBERTRACE NMAP TRAINING LAB
=================================

Welcome to the FTP training server.

Explore the public directory.
EOF

cat > "$FTP_DIR/pub/notes.txt" <<'EOF'
Training environment: CyberTrace

Service: FTP
Access: Anonymous
Port: 21

This file is intentionally exposed.
EOF

chown -R root:root "$FTP_DIR"
chmod -R 755 "$FTP_DIR"

cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO

anonymous_enable=YES
no_anon_password=YES
anon_root=${FTP_DIR}

local_enable=YES
write_enable=NO

dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

ftpd_banner=Welcome to CyberTrace FTP Training Server
EOF

# ------------------------------------------------
# 4. CONFIGURE SSH - PORT 22
# ------------------------------------------------

echo "[4/8] Configuring SSH..."

mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-nmap-lab.conf <<EOF
PasswordAuthentication yes
PermitRootLogin no
EOF

sshd -t

# ------------------------------------------------
# 5. CONFIGURE HTTP - PORT 80
# ------------------------------------------------

echo "[5/8] Configuring HTTP..."

mkdir -p "$WEB_DIR/backup"

cat > "$WEB_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Nmap Training Target</title>
</head>
<body>

<h1>Welcome to CyberTrace</h1>

<h2>Nmap Network Reconnaissance Lab</h2>

<p>Target server is operational.</p>

<p>Explore the available services.</p>

</body>
</html>
EOF

cat > "$WEB_DIR/backup/index.html" <<'EOF'
<h1>Backup Directory</h1>
<p>Welcome to the exposed backup directory.</p>
<p>Look around for interesting information.</p>
EOF

cat > "$WEB_DIR/backup/notes.txt" <<'EOF'
CYBERTRACE INTERNAL TRAINING NOTES

Target: Debian Linux
Services: FTP / SSH / HTTP / Telnet / SMB / MariaDB

This directory is intentionally exposed for enumeration.
EOF

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /backup/ {
        autoindex on;
    }
}
EOF

nginx -t

# ------------------------------------------------
# 6. CONFIGURE TELNET - PORT 23
# ------------------------------------------------

echo "[6/8] Configuring Telnet..."

TELNETD_BIN="$(command -v telnetd)"

# Remove previous Telnet entry to avoid duplicates.
sed -i '/^[[:space:]]*telnet[[:space:]]/d' /etc/inetd.conf

# Enable Telnet through inetd.
echo "telnet stream tcp nowait root ${TELNETD_BIN} telnetd" \
    >> /etc/inetd.conf

# ------------------------------------------------
# 7. CONFIGURE SMB - PORTS 139 AND 445
# ------------------------------------------------

echo "[7/8] Configuring Samba..."

mkdir -p "$SMB_DIR"

cat > "$SMB_DIR/readme.txt" <<'EOF'
=================================
 CYBERTRACE PUBLIC SMB SHARE
=================================

This is a public training share.

Use Nmap and SMB enumeration tools
to discover this resource.
EOF

cat > "$SMB_DIR/inventory.txt" <<'EOF'
TRAINING INVENTORY

Server: Debian
Department: IT
Environment: CyberTrace Lab
EOF

chown -R nobody:nogroup /srv/samba
chmod -R 755 /srv/samba

cat > /etc/samba/smb.conf <<'EOF'
[global]
    workgroup = WORKGROUP
    server role = standalone server
    security = user
    map to guest = Bad User
    guest account = nobody
    server min protocol = SMB2

[public]
    path = /srv/samba/public
    browseable = yes
    read only = yes
    guest ok = yes
    guest only = yes
    force user = nobody
EOF

testparm -s

# ------------------------------------------------
# 8. CONFIGURE MYSQL/MARIADB - PORT 3306
# ------------------------------------------------

echo "[8/8] Configuring MariaDB..."

cat > /etc/mysql/mariadb.conf.d/99-nmap-lab.cnf <<'EOF'
[mysqld]
bind-address = 0.0.0.0
EOF

# ------------------------------------------------
# CREATE TRAINING DATABASE
# ------------------------------------------------

echo "[+] Creating training database..."

systemctl enable mariadb
systemctl start mariadb

mariadb <<SQL

CREATE DATABASE IF NOT EXISTS ${DB_NAME};

CREATE TABLE IF NOT EXISTS ${DB_NAME}.users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50),
    role VARCHAR(50)
);

INSERT INTO ${DB_NAME}.users (username, role)
SELECT 'alice', 'student'
WHERE NOT EXISTS (
    SELECT 1 FROM ${DB_NAME}.users WHERE username = 'alice'
);

INSERT INTO ${DB_NAME}.users (username, role)
SELECT 'bob', 'administrator'
WHERE NOT EXISTS (
    SELECT 1 FROM ${DB_NAME}.users WHERE username = 'bob'
);

CREATE USER IF NOT EXISTS '${DB_USER}'@'%'
IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${DB_USER}'@'%'
IDENTIFIED BY '${DB_PASSWORD}';

GRANT SELECT ON ${DB_NAME}.* TO '${DB_USER}'@'%';

FLUSH PRIVILEGES;

SQL

# ------------------------------------------------
# START AND ENABLE SERVICES
# ------------------------------------------------

echo ""
echo "[+] Enabling all training services..."

systemctl enable ssh
systemctl enable vsftpd
systemctl enable nginx
systemctl enable smbd
systemctl enable openbsd-inetd

systemctl restart ssh
systemctl restart vsftpd
systemctl restart nginx
systemctl restart smbd
systemctl restart openbsd-inetd
systemctl restart mariadb

# ------------------------------------------------
# FINAL VERIFICATION
# ------------------------------------------------

echo ""
echo "=============================================="
echo "       INSTALLATION COMPLETED"
echo "=============================================="

echo ""
echo "[+] Listening TCP ports:"
ss -lnt

echo ""
echo "[+] Network interfaces:"
ip -br addr

echo ""
echo "[+] Service status:"

for service in ssh vsftpd nginx smbd openbsd-inetd mariadb; do
    if systemctl is-active --quiet "$service"; then
        echo "[OK] $service"
    else
        echo "[ERROR] $service"
    fi
done

echo ""
echo "=============================================="
echo "         TRAINING CREDENTIALS"
echo "=============================================="

echo "Linux user:       ${LAB_USER}"
echo "Linux password:   ${LAB_PASSWORD}"

echo ""
echo "FTP:              Anonymous access enabled"
echo "SMB:              Guest share enabled"

echo ""
echo "Database:         ${DB_NAME}"
echo "Database user:    ${DB_USER}"
echo "Database password: ${DB_PASSWORD}"

echo ""
echo "=============================================="
echo "       CYBERTRACE NMAP LAB READY"
echo "=============================================="

echo ""
echo "[!] Remember to use an isolated network."
echo "[!] These credentials are for training only."
