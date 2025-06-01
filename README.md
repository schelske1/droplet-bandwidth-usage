# DigitalOcean Outbound Bandwidth Monitor 🛰️

A lightweight Bash script that queries DigitalOcean’s Monitoring API to estimate **outbound traffic over the last 30 days** for a single Droplet.
If usage crosses a configurable threshold (default **950 GiB**), the script exits with code `2`, so you can hook in automated shutdown or alerting logic.

---

## ✨ Features

* **Official Monitoring API** – no scraping or guess-work.
* **True 30-day window** – sums *Mbps × real sampling intervals* for accuracy.
* **Dependency & token checks** up-front.
* **Human-readable summary** + an append-only log (`~/do_bandwidth.log`).
* **Configurable threshold** triggers whatever mitigation you script (PM2 stop, power-off, Slack ping, …).

---

## 📂 Script Overview

- **`check-do-outbound-bandwidth.sh`**  
  Queries the DigitalOcean API to check outbound bandwidth usage. Exits with code `2` if usage exceeds a defined threshold.

- **`shutdown-if-over-bandwidth.sh`**  
  Wrapper script that runs `check-do-outbound-bandwidth.sh` and, if exit code `2` is returned, executes custom logic to shut down services or send alerts.

---

## 🖥️ Prerequisites

| Requirement | Why it’s needed |
|-------------|-----------------|
| Bash 4+     | Script language |
| `curl`      | HTTP requests   |
| `jq`        | JSON parsing    |
| `awk`, `bc` | Math / unit conversion |
| GNU `date`  | ISO timestamps  |
| DigitalOcean **Personal Access Token** → `DO_API_TOKEN` | Auth for API calls |
| The Droplet’s **numeric ID** → `DROPLET_ID` | Tells the API which host |
| **DigitalOcean Monitoring enabled** (metrics agent installed) | Provides bandwidth metrics |

> **macOS tip** – install missing CLI tools with Homebrew:
> `brew install jq coreutils gnu-sed gawk bc`

---

## 📈 Enable DigitalOcean Monitoring (install the metrics agent)
To enable monitoring when creating a new Droplet, simply check the “Monitoring” option in the Control Panel or add --monitoring to your doctl compute droplet create command. Monitoring will be active from first boot.

To enable monitoring on an existing Droplet:

   ```bash
   # SSH into the Droplet as root or a sudo-capable user
   ssh root@your_droplet_ip
   
   # Install or upgrade the DigitalOcean metrics agent
   curl -sSL https://repos.insights.digitalocean.com/install.sh | sudo bash
   
   # Verify the agent is running
   systemctl status do-agent
   ```

---

## 🔑 Creating `DO_API_TOKEN`

1. Sign in to the [DigitalOcean Control Panel](https://cloud.digitalocean.com/account/api/tokens).
2. **Generate New Token** → give it a name → *uncheck* **Write** (read-only is enough) → **Create Token**.
3. Set up the file that the script will use to load your API token:
      ```bash
      mkdir -p ~/.config/cron-secrets
      nano ~/.config/cron-secrets/env
      ```
4. Paste your API token into the file:
      ```
      DO_API_TOKEN="your_token_here"
      ```
5. Secure the file so only your user can read it:
      ```bash
      chmod 600 ~/.config/cron-secrets/env
      ```

---

## 🔍 Finding `DROPLET_ID`

* **Control Panel** – open the Droplet; the numeric ID is in the URL and in the **Metadata** sidebar.
* **`doctl` CLI** (recommended):

  ```bash
  doctl compute droplet list --output json | jq -r '.[] | "\(.id)\t\(.name)"'
  ```

---

## ⚙️ Configuration

Inside **`check-do-outbound-bandwidth.sh`**, update the configuration section:

```bash
# === CONFIGURATION ===
: "${HOME:=/home/<YOUR_USER_NAME>}" # TODO (1): Provide your user name

DROPLET_ID="$DROPLET_ID" # TODO (2): Provide your Droplet ID
INTERFACE="public"
DIRECTION="outbound"
THRESHOLD_GIB=950 # TODO (3): Update to accurate threshold for your Droplet
LOG_FILE="$HOME/logs/do_bandwidth.log"
```

---

## 🚀 Running Manually

```bash
chmod +x check-do-outbound-bandwidth.sh
./check-do-outbound-bandwidth.sh
```

Example output:

```
[*] Querying DigitalOcean bandwidth metrics (Mbps) for the last 30 days...
Found result index: 0
[✓] 2025-05-30T22:11:02Z - Estimated outbound bandwidth over last 30 days:
  Start:       2025-04-30T22:11:02Z
  End:         2025-05-30T22:11:02Z
  Data points: 1440
  Actual span: 2025-04-30 22:00 to 2025-05-30 22:00
  Bytes:       1 033 482 123 456
  GiB:         962.09
  Avg kbps:    318.42
```

### Exit codes

| Code | Meaning                                 |
| ---- | --------------------------------------- |
| `0`  | Success, usage ≤ threshold              |
| `1`  | Missing dependency or API failure       |
| `2`  | Usage **> `THRESHOLD_GIB` GiB** (alert) |

---

## ⏰ Automating with Cron

```bash
chmod +x shutdown-if-over-bandwidth.sh
```

Respond to exit code 2 in the wrapper script (shutdown-if-over-bandwidth.sh) with shutdowns, alerts, or other custom actions.

Set the script to run once every hour, at minute 0 (i.e., the top of the hour), and log its output:

```bash
crontab -e
```

```cron
0 * * * * /usr/local/bin/shutdown-if-over-bandwidth.sh >> /var/log/pm2-bandwidth-shutdown.log 2>&1
```

---

## 📜 License

[MIT](LICENSE)
