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
3. Copy the token **once** and export it:

   ```bash
   export DO_API_TOKEN="YOUR_API_TOKEN"
   ```

---

## 🔍 Finding `DROPLET_ID`

* **Control Panel** – open the Droplet; the numeric ID is in the URL and in the **Metadata** sidebar.
* **`doctl` CLI** (recommended):

  ```bash
  doctl compute droplet list --output json | jq -r '.[] | "\(.id)\t\(.name)"'
  ```

Then:

```bash
export DROPLET_ID="YOUR_DROPLET_ID"
```

---

## ⚙️ Configuration

Inside **`check-do-outbound-bandwidth.sh`**:

```bash
# User-tweakable values
INTERFACE="public"      # or "private"
DIRECTION="outbound"    # or "inbound"
THRESHOLD_GIB=950       # change to taste (e.g. 900)
LOG_FILE="$HOME/do_bandwidth.log"
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

Run every hour at **HH:05** UTC (adjust as needed):

```cron
5 * * * * /usr/local/bin/check-do-outbound-bandwidth.sh
```

---

## 🔌 Example: Auto-Shutdown with PM2

`/usr/local/bin/pm2-bandwidth-guard.sh`

```bash
#!/bin/bash
/usr/local/bin/check-do-outbound-bandwidth.sh
EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 2 ]]; then
  TS="$(date)"
  echo "$TS: Exit code 2 — stopping and clearing all PM2 apps." | tee -a /var/log/pm2-monitor.log

  pm2 delete all        # stop & remove apps
  pm2 save --force      # persist empty state
else
  echo "$(date): Exit code $EXIT_CODE — no action taken." | tee -a /var/log/pm2-monitor.log
fi
```

Add *that* script to cron instead, or replace the PM2 commands with power-off, snapshot, PagerDuty alert, etc.

---

## 📝 Troubleshooting

* **`Missing DO_API_TOKEN`** – token not exported in the current shell.
* **`Failed to retrieve or parse bandwidth data.`** – metric stream may not exist yet (new Droplet) or the API returned an error; inspect with `curl -i`.
* **Unexpected threshold trips** – remember the script measures **rolling 30 days**, not calendar month quotas.
* **Script not found when run by cron** – make sure the script is placed in a directory that's in your system's `PATH`, such as `/usr/local/bin`, and that it has executable permissions (`chmod +x`).

---

## 📜 License

[MIT](LICENSE)
