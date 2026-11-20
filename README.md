# cPanel DNS Audit (`cp-dns-audit.sh`)

![cPanel DNS Audit Cover](./cpanel-dns-audit-cover.webp)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](./cp-dns-audit.sh)
[![License](https://img.shields.io/badge/license-GPL--3.0-green.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20cPanel%20%2F%20WHM%20%7C%20BIND9-orange.svg)](#requirements)

> 🇧🇷 **[Leia em Português (README-ptbr.md)](./README-ptbr.md)**

**cPanel DNS Audit** (`cp-dns-audit.sh` v2.0.0) is a Bash + Python3 (stdlib-only) CLI tool that performs deep server-wide audits of BIND9 / cPanel DNS zone files (`/var/named/*.db`). It validates zone syntax via `named-checkzone`, extracts MX records, traces `mail` A/CNAME records (including live IP resolution and CNAME loop detection), cross-checks `/etc/localdomains` and `/etc/remotedomains` to catch silent `ROUTING_MISMATCH` errors, and checks SPF/DKIM/DMARC authentication records.

---

## Features

- **Zone Syntax Validation:** Automatically invokes `named-checkzone -q` when installed on the server to catch broken SOA/NS/syntax errors.
- **MX & Mail Routing Audit:** Cross-references primary MX targets (Google Workspace, Microsoft 365, Zoho, Proton, etc.) against `/etc/localdomains` and `/etc/remotedomains` to flag `ROUTING_MISMATCH` issues that silently bounce local mail.
- **CNAME IP Tracing & Loop Detection:** Resolves `mail` CNAME targets to live IP addresses (or runs offline with `--no-dns-resolve`) and flags `CNAME_LOOP` misconfigurations.
- **Email Authentication Coverage:** Checks for SPF (`v=spf1`), DKIM (`_domainkey`), and DMARC (`_dmarc` / `v=DMARC1`) records per zone (`SKD` indicator).
- **Flexible Filtering & Outputs:** Audit all zones (`--all-zones`) or a single domain (`-D`), filter only failing zones (`-e, --only-issues`), and export as `table`, `json`, or `csv` to stdout, file (`-f`), or email (`-m`).
- **Automation-Ready Exit Codes:** Returns `0` when all audited zones are clean, `1` on runtime/usage errors, and `2` when one or more zones have warnings or critical issues.

---

## Requirements

- Linux with Bash 4.0+ and Python 3.6+ (standard library only, zero external packages)
- BIND / cPanel zone directory (default `/var/named`)
- Optional: `named-checkzone` (for zone syntax checks), `mail` or `sendmail` (for `-m` email reports)

---

## Installation

```bash
git clone https://github.com/sr00t3d/cpanel-dns-audit.git
cd cpanel-dns-audit
chmod +x cp-dns-audit.sh
```

---

## Usage

```bash
# Audit all zones in /var/named
sudo ./cp-dns-audit.sh --all-zones

# Audit a single domain
sudo ./cp-dns-audit.sh -D example.com

# Show only zones with issues
sudo ./cp-dns-audit.sh --only-issues

# Export full audit as JSON to a file
sudo ./cp-dns-audit.sh -o json -f /tmp/dns-audit.json

# Export as CSV (offline mode without live CNAME DNS resolution)
sudo ./cp-dns-audit.sh --no-dns-resolve -o csv > dns-audit.csv

# Audit a custom zone directory and email the report
sudo ./cp-dns-audit.sh -d /var/named -m ops@example.com
```

### CLI Options

| Flag | Description |
| :--- | :--- |
| `--all-zones` | Audit all `*.db` zone files in `--dir` (default) |
| `-d, --dir <path>` | BIND/Named zone directory (default: `/var/named`) |
| `-D, --domain <domain>` | Audit a single domain zone file |
| `-e, --only-issues` | Display only zones with syntax, MX, routing, or auth issues |
| `--no-dns-resolve` | Skip live DNS resolution of `mail` CNAME targets |
| `-o, --output <fmt>` | Output format: `table` (default), `json`, `csv` |
| `-f, --file <path>` | Save report output to file |
| `-m, --email <addr>` | Email report via `mail` or `sendmail` |
| `-q, --quiet` | Suppress progress logs |
| `--no-color` | Disable ANSI colors |
| `-V, --version` | Show version and exit |
| `-h, --help` | Show help message and exit |

---

## Real Output Example

Captured on an AlmaLinux 8.10 / cPanel test container auditing 3 zones (healthy local mail, Google Workspace routing mismatch, and broken CNAME loop without MX):

```text
============================================================================================================================
 CPANEL DNS AUDIT v2.0.0 - [cpanel-test.local] | Dir: /tmp/dns-audit-fixture | Zones: 3
============================================================================================================================
DOMAIN                     | ROUTING | PRIMARY MX                   | MAIL/IP                | AUTH  | STATUS   | ISSUES
----------------------------------------------------------------------------------------------------------------------------
broken.example.com         | UNKNOWN | -                            | CNAME:LOOP             | ---   | CRITICAL | NO_MX,CNAME_LOOP,NO_SPF,NO_DMARC
healthy.example.com        | LOCAL   | mail.healthy.example.com     | A:192.0.2.10           | SKD   | OK       | clean
workspace.example.com      | LOCAL   | aspmx.l.google.com           | CNAME:142.250.139.121  | S--   | CRITICAL | ROUTING_MISMATCH,NO_DMARC
============================================================================================================================
 Summary: 3 zone(s) | OK: 1 | WARN: 0 | CRITICAL: 2 | Auth Legend: S=SPF K=DKIM D=DMARC
============================================================================================================================
```

---

## License

Licensed under the [GPL-3.0 License](./LICENSE).
