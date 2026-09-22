# Setting Up OpenCode as a Backend Server

This guide explains how to run opencode as a headless HTTP backend server using systemd, enabling Spark (and other clients) to connect remotely.

## Prerequisites

- Linux server (Ubuntu 22.04+ recommended)
- OpenCode installed (`npm install -g opencode` or binary)
- Node.js 18+ (if using npm installation)
- A valid opencode configuration (`~/.config/opencode/`)

## 1. Create the opencode Configuration

Ensure your opencode config exists at `~/.config/opencode/opencode.json`:

```json
{
  "provider": {
    "your-provider": {
      "apiKey": "your-api-key"
    }
  }
}
```

Custom agents placed under `~/.config/opencode/agents/` appear automatically in
Spark's agent picker. When authoring agents whose output renders in chat, prefer
inline SVG data-URI images for charts and one-label-per-cell markdown tables —
both render natively in the app.

## 2. Create a systemd Service

Create the service file at `/etc/systemd/system/opencode.service`:

```ini
[Unit]
Description=OpenCode Backend Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=your-username
Group=your-username
WorkingDirectory=/home/your-username

# Environment
Environment=HOME=/home/your-username
Environment=PATH=/home/your-username/.nvm/versions/node/v20.11.1/bin:/usr/local/bin:/usr/bin:/bin

# Set a server password for authentication
Environment=OPENCODE_SERVER_PASSWORD=your-secure-password

# Start the server
ExecStart=/home/your-username/.nvm/versions/node/v20.11.1/bin/opencode serve --port 4096 --hostname 0.0.0.0

# Restart policy
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/your-username/.config/opencode
ReadWritePaths=/tmp

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=opencode

[Install]
WantedBy=multi-user.target
```

**Important:** Replace `your-username`, `your-secure-password`, and the Node.js path with your actual values.

### Find Your Node.js Path

```bash
which opencode
# or
which node
```

## 3. Enable and Start the Service

```bash
# Reload systemd to pick up the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable opencode.service

# Start the service now
sudo systemctl start opencode.service

# Check status
sudo systemctl status opencode.service
```

## 4. Verify the Server is Running

```bash
# Health check
curl http://localhost:4096/global/health

# Expected response:
# {"healthy":true,"version":"1.18.4"}

# With authentication
curl -u opencode:your-secure-password http://localhost:4096/global/health
```

## 5. Configure the Spark App

1. Open the Spark app on your Android device
2. Enter the server details:
   - **Host:** `your-server-ip` (e.g., `192.168.1.100`)
   - **Port:** `4096`
   - **Password:** `your-secure-password`
3. Tap **Connect**

## 6. Firewall Configuration

If you're running a firewall, open port 4096:

```bash
# UFW (Ubuntu)
sudo ufw allow 4096/tcp

# firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-port=4096/tcp
sudo firewall-cmd --reload
```

For production, consider running behind a reverse proxy (nginx/caddy) with TLS.

## 7. Using Custom Agents

Once connected, agents defined on the server show up in Spark's agent picker.
To use one:

1. Open or create a session
2. Tap the agent selector (bottom-left of the composer)
3. Select your agent and prompt it

Restart the opencode service after adding or modifying agents.

## 8. Managing the Service

```bash
# View logs
sudo journalctl -u opencode.service -f

# Restart the service
sudo systemctl restart opencode.service

# Stop the service
sudo systemctl stop opencode.service

# Disable auto-start on boot
sudo systemctl disable opencode.service
```

## 9. Optional: Reverse Proxy with TLS

For secure remote access, use nginx as a reverse proxy:

```nginx
server {
    listen 443 ssl;
    server_name opencode.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/opencode.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/opencode.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:4096;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE support
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;
    }
}
```

## Troubleshooting

### Service fails to start

```bash
sudo journalctl -u opencode.service -n 50 --no-pager
```

Common issues:
- **Wrong Node.js path:** Use `which opencode` to find the correct path
- **Permission denied:** Ensure the user has read access to `~/.config/opencode/`
- **Port in use:** Check if another process is using port 4096: `ss -tlnp | grep 4096`

### Connection refused from Spark app

1. Verify the server is running: `sudo systemctl status opencode.service`
2. Check the server is listening on `0.0.0.0:4096` (not just `127.0.0.1`)
3. Verify firewall rules allow port 4096
4. Ensure the password matches what's configured in the service file

### Agent not appearing in Spark app

1. Verify the agent file exists: `ls ~/.config/opencode/agents/`
2. Restart the opencode service after adding/modifying agents: `sudo systemctl restart opencode.service`
3. Check logs for agent loading errors: `sudo journalctl -u opencode.service | grep agent`
