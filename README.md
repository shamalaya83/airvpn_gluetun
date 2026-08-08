# AirVPN Best Server Selector

A lightweight shell script that automatically selects the best available **AirVPN server** for [Gluetun](https://github.com/qdm12/gluetun).

The script retrieves the current AirVPN server status, filters servers according to configurable criteria, checks their exit IP against multiple reputation sources, and finally starts Gluetun using the selected server.

It can also be used in **forced-server mode** when a specific AirVPN server needs to be selected manually.

---

## ✨ Features

- 🌍 Select servers from a configurable country
- ⭐ Prioritize the server recommended by AirVPN
- 📊 Filter servers by health and bandwidth
- 🚦 Configurable minimum bandwidth requirement
- 🧅 Optional Tor exit-node detection
- 🛡️ Optional DroneBL / DNSBL checks
- 🔎 Optional IPQualityScore checks
- 🧩 Verify that the server exists in Gluetun's AirVPN server list
- 🚀 Support for manually forced servers
- 🐳 Designed to run inside Docker/Gluetun
- ⚙️ Configuration through environment variables
- 🔢 Configurable maximum number of server attempts

---

## 🔄 How it works

The script follows this general workflow:

```text
                    ┌─────────────────────┐
                    │      Start script   │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  FORCED_SERVER set? │
                    └──────────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    │                     │
                   YES                   NO
                    │                     │
                    ▼                     ▼
             Set SERVER_NAMES      Query AirVPN API
                    │                     │
                    │                     ▼
                    │              Filter candidates
                    │                     │
                    │                     ▼
                    │              Check Gluetun
                    │                     │
                    │                     ▼
                    │              Resolve exit IP
                    │                     │
                    │                     ▼
                    │              DroneBL check
                    │                     │
                    │                     ▼
                    │                Tor check
                    │                     │
                    │                     ▼
                    │               IPQS check
                    │                     │
                    │                     ▼
                    │              Select server
                    │                     │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ SERVER_NAMES set    │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ gluetun-entrypoint  │
                    └─────────────────────┘
```

---

## 📋 Requirements

The script is designed primarily for the **Gluetun Alpine-based Docker environment**.

Required commands:

- `sh`
- `curl`
- `jq`
- `dig`
- `awk`
- `grep`

`curl`, `jq`, and `dig` are automatically installed when missing using Alpine's `apk`.

The script also expects the Gluetun AirVPN server database to be available at:

```text
/gluetun/servers/airvpn.json
```

---

## ⚙️ Configuration

The main configuration is located at the beginning of the script.

```sh
GLUETUN_SERVERS_JSON="/gluetun/servers/airvpn.json"
COUNTRY="Netherlands"
MAX_ATTEMPTS=10

USE_IPQS_CHECK="${USE_IPQS_CHECK:-true}"
DRONEBL_CHECK="${DRONEBL_CHECK:-true}"
TOR_CHECK="${TOR_CHECK:-true}"

MIN_BANDWIDTH="${MIN_BANDWIDTH:-0}"

FORCED_SERVER="${FORCED_SERVER:-}"
```

### Country

The country used to select AirVPN servers:

```sh
COUNTRY="Netherlands"
```

For example:

```sh
COUNTRY="Germany"
```

or:

```sh
COUNTRY="Switzerland"
```

The value must match the country name returned by the AirVPN API.

---

## 🚦 Minimum bandwidth

`MIN_BANDWIDTH` defines the minimum server bandwidth required for a server to become a candidate.

```sh
MIN_BANDWIDTH=0
```

`0` means that no minimum bandwidth is enforced.

Example:

```sh
MIN_BANDWIDTH=50
```

Only servers satisfying:

```text
bw >= 50
```

will be considered.

This can be overridden through Docker:

```yaml
environment:
  - MIN_BANDWIDTH=50
```

---

## 🧅 Tor check

The Tor check can be enabled or disabled independently.

Enabled:

```sh
TOR_CHECK=true
```

Disabled:

```sh
TOR_CHECK=false
```

When enabled, the script downloads the official Tor exit-node list and checks the resolved AirVPN exit IP against it.

Example:

```yaml
environment:
  - TOR_CHECK=true
```

---

## 🛡️ DroneBL check

DroneBL/DNSBL checking can be enabled or disabled:

```sh
DRONEBL_CHECK=true
```

or:

```sh
DRONEBL_CHECK=false
```

The script checks the exit IP against several DNSBL services.

Currently configured lists include:

```text
dnsbl.dronebl.org
rbl.efnetrbl.org
dnsbl.swiftbl.net
combined.abuse.ch
```

If the IP is found on any of these lists, the server is rejected.

---

## 🔎 IPQualityScore

IPQualityScore can also be enabled or disabled:

```sh
USE_IPQS_CHECK=true
```

or:

```sh
USE_IPQS_CHECK=false
```

The script currently uses the IPQualityScore IP reputation API to detect whether an exit IP is identified as a Tor node.

You must provide your API key:

```sh
IPQS_API_KEY="YOUR_API_KEY"
```

---

## 🚀 Forced server mode

If `FORCED_SERVER` is set, **all server selection and reputation checks are skipped**.

Example:

```sh
FORCED_SERVER="Alchiba"
```

The script will simply set:

```text
SERVER_NAMES=Alchiba
```

and start Gluetun.

This is particularly useful for troubleshooting or temporarily pinning the VPN connection to a specific server.

Docker example:

```yaml
environment:
  - FORCED_SERVER=Alchiba
```

To return to automatic selection:

```yaml
environment:
  - FORCED_SERVER=
```

---

## 🐳 Docker example

Example environment configuration:

```yaml
environment:
  - COUNTRY=Netherlands
  - MIN_BANDWIDTH=50
  - MAX_ATTEMPTS=10
  - TOR_CHECK=true
  - DRONEBL_CHECK=true
  - USE_IPQS_CHECK=true
  - FORCED_SERVER=
```

With this configuration the script will:

1. Search for AirVPN servers in the Netherlands
2. Ignore servers with less than `50` bandwidth
3. Try at most `10` servers
4. Check Tor exit-node status
5. Check DNSBL reputation
6. Check IPQualityScore
7. Select the first server passing all checks
8. Start Gluetun

---

## 🔐 API Keys

The script requires an AirVPN API key and optionally an IPQualityScore API key.

```sh
AIRVPN_API_KEY="YOUR_AIRVPN_API_KEY"
IPQS_API_KEY="YOUR_IPQS_API_KEY"
```

**Do not commit API keys to GitHub.**

For Docker deployments, it is recommended to provide them through environment variables or Docker secrets rather than storing them directly in the script.

For example:

```yaml
environment:
  - AIRVPN_API_KEY=${AIRVPN_API_KEY}
  - IPQS_API_KEY=${IPQS_API_KEY}
```

And in your `.env` file:

```dotenv
AIRVPN_API_KEY=your_airvpn_key
IPQS_API_KEY=your_ipqs_key
```

Make sure `.env` is included in `.gitignore`.

---

## 🧠 Server selection

The script first retrieves AirVPN's current server status.

Servers are filtered using:

```text
Country
   ↓
Health = OK
   ↓
Bandwidth available
   ↓
Minimum bandwidth
   ↓
Valid IPv4
```

The server recommended by AirVPN (`server_best`) is moved to the beginning of the candidate list.

The script then evaluates candidates sequentially.

---

## 🔍 Reputation checks

For each candidate, the script resolves its external VPN IP using:

```text
<server>_exit.airservers.org
```

For example:

```text
Alchiba_exit.airservers.org
```

The resulting IP is then checked against the enabled reputation systems.

### Check order

```text
Gluetun server exists?
        │
        ▼
Resolve exit IP
        │
        ▼
DroneBL
        │
        ▼
Tor
        │
        ▼
IPQualityScore
        │
        ▼
Server accepted
```

If any enabled check fails, the server is rejected and the next candidate is evaluated.

---

## 📊 Example output

A successful run looks similar to:

```text
🌍 Selecting the best AirVPN server in Netherlands...

⚙️ Configuration:
   IPQualityScore check : true
   DroneBL check        : true
   Tor check            : true
   Minimum bandwidth    : 50
   Maximum attempts     : 10

📡 Downloading Tor exit node list...
🧅 Tor check enabled.

📡 Downloading AirVPN server data...

✨ AirVPN recommends: Alchiba

🔎 Found 24 candidate server(s).

============================================================
🔎 Checking server: Alchiba
   AirVPN IP       : 185.xxx.xxx.xxx
   Bandwidth       : 72 / 100
   Current load    : 14%
============================================================

🔎 Checking if Alchiba exists in Gluetun server list...
🌐 Exit IP for Alchiba is 185.xxx.xxx.xxx

🔎 DroneBL check for 185.xxx.xxx.xxx...
✅ DroneBL check passed.

🔎 Tor check for 185.xxx.xxx.xxx...
✅ Tor check passed.

🔎 IPQualityScore check for 185.xxx.xxx.xxx...
✅ IPQualityScore check passed.

============================================================
✅ SELECTED SERVER
   Server  : Alchiba
   AirVPN  : 185.xxx.xxx.xxx
   Exit IP : 185.xxx.xxx.xxx
   BW      : 72 / 100
============================================================

🌐 Exported SERVER_NAMES=Alchiba
```

---

## ❌ Rejected server example

If a server fails one of the checks:

```text
🔎 Tor check for 185.xxx.xxx.xxx...
⛔ 185.xxx.xxx.xxx is a Tor exit node. Skipping.
```

The script automatically continues with the next candidate.

---

## 🔧 Environment variables

| Variable | Default | Description |
|---|---:|---|
| `COUNTRY` | `Netherlands` | AirVPN server country |
| `MAX_ATTEMPTS` | `10` | Maximum number of servers evaluated |
| `MIN_BANDWIDTH` | `0` | Minimum required bandwidth |
| `TOR_CHECK` | `true` | Enable Tor exit-node detection |
| `DRONEBL_CHECK` | `true` | Enable DNSBL checks |
| `USE_IPQS_CHECK` | `true` | Enable IPQualityScore |
| `FORCED_SERVER` | empty | Force a specific AirVPN server |
| `AIRVPN_API_KEY` | — | AirVPN API key |
| `IPQS_API_KEY` | — | IPQualityScore API key |

---

## 🧪 Example configurations

### Normal automatic selection

```yaml
environment:
  - COUNTRY=Netherlands
  - MIN_BANDWIDTH=0
  - TOR_CHECK=true
  - DRONEBL_CHECK=true
  - USE_IPQS_CHECK=true
  - FORCED_SERVER=
```

### High-bandwidth servers only

```yaml
environment:
  - COUNTRY=Netherlands
  - MIN_BANDWIDTH=75
  - TOR_CHECK=true
  - DRONEBL_CHECK=true
  - USE_IPQS_CHECK=true
```

### Disable Tor check

```yaml
environment:
  - TOR_CHECK=false
```

### Disable all reputation checks

```yaml
environment:
  - TOR_CHECK=false
  - DRONEBL_CHECK=false
  - USE_IPQS_CHECK=false
```

### Force a specific server

```yaml
environment:
  - FORCED_SERVER=Alchiba
```

---

## ⚠️ Notes

### AirVPN API availability

Server information depends on the AirVPN status API. If the API is unavailable, the script exits without selecting a server.

### DNS resolution

The script relies on DNS resolution of:

```text
<server>_exit.airservers.org
```

If the external IP cannot be resolved, that candidate is skipped.

### Gluetun server database

The selected server must exist in:

```text
/gluetun/servers/airvpn.json
```

Otherwise, the candidate is rejected.

### API keys

Never commit real API keys to the repository.

Use environment variables, `.env`, Docker secrets, or another secure secret-management mechanism.

---

## 📄 License

Choose a license appropriate for your project. For example, if you want a permissive open-source license, you can use the **MIT License**.

---

## ⭐ Contributing

Pull requests and improvements are welcome.

If you find a problem or have an idea for improving server selection or reputation checks, feel free to open an issue.