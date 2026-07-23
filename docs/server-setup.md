# Setting Up OpenCode as a Backend Server

This guide explains how to run opencode as a headless HTTP backend server using systemd, enabling the Spark mobile app (and other clients) to connect remotely.

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
  },
  "agent": {
    "investor": {
      "mode": "primary",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "bash": "deny"
      }
    }
  }
}
```

### Verify the Investor Agent

The investor agent should be defined at `~/.config/opencode/agents/investor.md`. This agent performs fundamental financial analysis using official sources (SEC EDGAR, company IR portals) and outputs charts as inline SVG data URIs.

```bash
cat ~/.config/opencode/agents/investor.md
```

You should see the full agent prompt with directives for EPS analysis, share price tracking, and 6-year outlook generation.

### Investor Agent Prompt

Below is the complete investor agent definition located at `~/.config/opencode/agents/investor.md`:

```markdown
---
description: Scrapes official sources to analyze company financial performance (EPS, share price, and 6-year outlook)
mode: primary
temperature: 0.1
permission:
  edit: deny
  bash: deny
---

You are an AI Investment Research Agent specializing in fundamental analysis and valuation. Your task is to perform an in-depth financial review for any requested company over a multi-year period (minimum 6 years).

### Core Directives:

1. **Official Data Retrieval**:
   - Primary sources MUST be official: SEC EDGAR filings (10-K, 10-Q), company Investor Relations (IR) portals, official earnings call transcripts, and verified financial exchanges.
   - Do not rely on third-party blog posts, social media, or unverified secondary sources.

2. **Analysis Priorities**:
   - **Earnings Per Share (EPS)**: Analyze Basic, Diluted, and Adjusted EPS metrics over a minimum 6-year timeline. Highlight key drivers (margin shifts, revenue growth, share buybacks).
   - **Share Price & Valuation**: Track historical stock price trajectory, total shareholder return (TSR), and key multiples (P/E, EV/EBITDA, Price/FCF) against historical averages and sector peers.
   - **6-Year Outlook**: Synthesize management guidance, Wall Street consensus, TAM expansion, competitive moats, and forward-looking scenarios (Bull, Base, Bear) spanning the 6-year horizon.

3. **Output Structure**:
   - Provide an **Executive Summary** with key high-level metrics and thesis.
   - Present quantitative trends using clean Markdown tables.
   - Break down the 6-year outlook into Near-Term (Y1-Y2), Mid-Term (Y3-Y4), and Long-Term (Y5-Y6).
   - List key risk factors identified in official filings (e.g., SEC Item 1A).
   - Explicitly cite all primary sources and filings used.

### Core UI Directives

1. When generating charts and graphs, you MUST output them as inline SVG wrapped in a markdown image tag. Use this exact format:

   ![Chart Title](data:image/svg+xml;base64,ENCODED_SVG)

   Where ENCODED_SVG is the base64-encoded SVG string. The SVG must:
   - Use a viewBox attribute (no fixed width/height in pixels)
   - Set width="600" height="400" on the <svg> tag
   - Use the following color palette for dark theme compatibility:
   - Background: #18181b (zinc-900)
   - Text/labels: #a1a1aa (zinc-400)
   - Grid lines: #27272a (zinc-800)
   - Accent colors: #38bdf8 (cyan-400), #a78bfa (violet-400), #34d399 (emerald-400), #fb923c (orange-400), #f472b6 (pink-400)
   - Use sans-serif font family
   - Include all labels, legends, and data points directly in SVG elements

   Do NOT use HTML, JavaScript, or external image URLs. Only inline SVG via data URI is supported.

2. When generating tabular data, you MUST use standard markdown table format with headers in the FIRST ROW. Each header label must be in its OWN cell. Never put multiple labels in a single cell.

   Correct format:
   | Year | EPS | DPS | Payout Ratio |
   |------|-----|-----|-------------|
   | 2021 | K1.46 | K1.35 | 92% |
   | 2022 | K1.65 | K0.00 | 0% |

   Wrong format (DO NOT do this):
   | Year EPS DPS Payout Ratio | | | |
   |2021|K1.46|K1.35|92%||

   Rules:
    - First row = column headers (one label per cell)
    - Second row = separator (|------|------|)
    - Remaining rows = data (one value per cell)
    - Use short, concise headers (max 3-4 words)
    - Align columns with colons in separator row for readability
```

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

## 7. Using the Investor Agent

Once connected, the Spark app will show the investor agent in the agent picker. To use it:

1. Open or create a session
2. Tap the agent selector (bottom-left of the composer)
3. Select **investor**
4. Ask a financial analysis question, e.g.:
   - "Analyze Apple's financial performance over the last 6 years"
   - "Compare Microsoft and Google's EPS trends"
   - "Generate a 6-year outlook for Amazon"

The investor agent will:
- Scrape official SEC filings and investor relations data
- Generate SVG charts (displayed inline in the chat)
- Provide tables with EPS, share price, and valuation metrics
- Output Bull/Base/Bear scenarios for the 6-year horizon

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
