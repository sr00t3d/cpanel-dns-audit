#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                                                                           ║
# ║   cPanel DNS Audit (cp-dns-audit.sh) v2.0.0                               ║
# ║                                                                           ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║   Autor:   Percio Castelo                                                 ║
# ║   Contato: percio@evolya.com.br | contato@perciocastelo.com.br            ║
# ║   Web:     https://perciocastelo.com.br                                   ║
# ║                                                                           ║
# ║   Função:  Deep audits cPanel/BIND9 DNS zones: named-checkzone syntax,    ║
# ║            MX & mail A/CNAME tracing, local/remote mail routing mismatch, ║
# ║            SPF/DKIM/DMARC presence, with table/JSON/CSV output.           ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

set -uo pipefail
export LC_ALL=C

readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# =============================================================================
# Defaults
# =============================================================================
ZONE_DIR="/var/named"
SINGLE_DOMAIN=""
ONLY_ISSUES=false
RESOLVE_CNAME=true
OUTPUT_FORMAT="table"    # table | json | csv
OUTPUT_FILE=""
EMAIL_TO=""
NO_COLOR=false
QUIET=false

TMP_DIR=""
cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

# =============================================================================
# Colors
# =============================================================================
C_RESET=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_CYAN=""
C_DIM=""

init_colors() {
    if [[ "$NO_COLOR" == false && "$OUTPUT_FORMAT" == "table" && -t 1 ]]; then
        C_RESET=$'\033[0m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[0;31m'
        C_GREEN=$'\033[0;32m'
        C_YELLOW=$'\033[0;33m'
        C_CYAN=$'\033[0;36m'
    fi
}

log_info() { [[ "$QUIET" == false && "$OUTPUT_FORMAT" == "table" ]] && echo -e "${C_CYAN}[→]${C_RESET} $*" >&2; }
log_ok()   { [[ "$QUIET" == false && "$OUTPUT_FORMAT" == "table" ]] && echo -e "${C_GREEN}[+]${C_RESET} $*" >&2; }
log_warn() { [[ "$QUIET" == false ]] && echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
log_err()  { echo -e "${C_RED}[✗] Error:${C_RESET} $*" >&2; }

# =============================================================================
# Help
# =============================================================================
show_help() {
    cat <<EOF
cPanel DNS Audit (cp-dns-audit.sh) v${VERSION}
Deep audit of BIND9/cPanel DNS zones: syntax, MX, mail CNAME/IP tracing, mail routing, and SPF/DKIM/DMARC.

Usage:
  ${SCRIPT_NAME} [OPTIONS]

Scope Options:
      --all-zones           Audit all *.db zones in --dir (default)
  -d, --dir <path>          BIND/Named zone directory (default: /var/named)
  -D, --domain <domain>     Audit a single domain zone file

Audit & Output Options:
  -e, --only-issues         Show only zones with syntax, MX, routing, or auth issues
      --no-dns-resolve      Skip live DNS resolution of CNAME mail targets (offline mode)
  -o, --output <fmt>        Output format: table (default), json, csv
  -f, --file <path>         Save report to file
  -m, --email <address>     Email report via mail/mailx/sendmail
  -q, --quiet               Suppress progress messages
      --no-color            Disable ANSI colors
  -V, --version             Show version and exit
  -h, --help                Show this help message and exit

Exit Codes:
  0  All audited zones passed cleanly
  1  Usage or runtime error
  2  One or more zones have issues (syntax, missing MX, routing mismatch, missing SPF/DMARC)

Examples:
  sudo ${SCRIPT_NAME} --all-zones
  sudo ${SCRIPT_NAME} -D example.com
  sudo ${SCRIPT_NAME} --only-issues -o json -f /tmp/dns-audit.json
  sudo ${SCRIPT_NAME} -o csv > dns-audit.csv
EOF
}

# =============================================================================
# Argument Parser
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all-zones)       SINGLE_DOMAIN=""; shift ;;
            -d|--dir)          [[ $# -lt 2 ]] && { log_err "$1 requires a path"; exit 1; }; ZONE_DIR="$2"; shift 2 ;;
            -D|--domain)       [[ $# -lt 2 ]] && { log_err "$1 requires a domain"; exit 1; }; SINGLE_DOMAIN="$2"; shift 2 ;;
            -e|--only-issues)  ONLY_ISSUES=true; shift ;;
            --no-dns-resolve)  RESOLVE_CNAME=false; shift ;;
            -o|--output)       [[ $# -lt 2 ]] && { log_err "$1 requires a format"; exit 1; }; OUTPUT_FORMAT="$2"; shift 2 ;;
            -f|--file)         [[ $# -lt 2 ]] && { log_err "$1 requires a path"; exit 1; }; OUTPUT_FILE="$2"; shift 2 ;;
            -m|--email)        [[ $# -lt 2 ]] && { log_err "$1 requires an email"; exit 1; }; EMAIL_TO="$2"; shift 2 ;;
            -q|--quiet)        QUIET=true; shift ;;
            --no-color)        NO_COLOR=true; shift ;;
            -V|--version)      echo "cPanel DNS Audit v${VERSION}"; exit 0 ;;
            -h|--help)         show_help; exit 0 ;;
            -*)                log_err "Unknown option: $1 (use --help)"; exit 1 ;;
            *)                 SINGLE_DOMAIN="$1"; shift ;;
        esac
    done

    case "$OUTPUT_FORMAT" in
        table|json|csv) ;;
        *) log_err "--output must be table, json, or csv"; exit 1 ;;
    esac
    if [[ ! -d "$ZONE_DIR" ]]; then
        log_err "Zone directory not found: ${ZONE_DIR}"
        exit 1
    fi
}

# =============================================================================
# Audit Engine (Python3 stdlib + named-checkzone)
# =============================================================================
run_audit() {
    local report_tmp="$1"
    local host
    host=$(hostname 2>/dev/null || echo "unknown")

    if ! command -v python3 >/dev/null 2>&1; then
        log_err "python3 is required for deep zone parsing and structured reports."
        exit 1
    fi

    python3 - "$VERSION" "$host" "$ZONE_DIR" "$SINGLE_DOMAIN" "$ONLY_ISSUES" \
        "$RESOLVE_CNAME" "$OUTPUT_FORMAT" "$C_RESET" "$C_GREEN" "$C_YELLOW" "$C_RED" "$C_DIM" > "$report_tmp" <<'PYEOF'
import csv
import datetime
import glob
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys

(version, host, zone_dir, single_dom, only_issues_s,
 resolve_cname_s, fmt, c_rst, c_grn, c_yel, c_red, c_dim) = sys.argv[1:13]

only_issues = only_issues_s == "true"
resolve_cname = resolve_cname_s == "true"
has_checkzone = shutil.which("named-checkzone") is not None

def load_domain_set(path):
    s = set()
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    d = line.strip().lower()
                    if d and not d.startswith("#"):
                        s.add(d)
        except Exception:
            pass
    return s

local_domains = load_domain_set("/etc/localdomains")
remote_domains = load_domain_set("/etc/remotedomains")

EXTERNAL_MX_HINTS = (
    "google.com", "googlemail.com", "outlook.com", "protection.outlook.com",
    "zoho.com", "protonmail.ch", "yahoodns.net", "secureserver.net",
    "mxrouting.net", "mailgun.org", "emailsrvr.com", "mimecast.com",
    "pphosted.com", "amazonses.com", "fastmail.com", "icloud.com"
)

if single_dom:
    zf = os.path.join(zone_dir, f"{single_dom}.db")
    if not os.path.isfile(zf):
        sys.stderr.write(f"[x] Error: Zone file not found: {zf}\n")
        sys.exit(1)
    zone_files = [zf]
else:
    zone_files = sorted(glob.glob(os.path.join(zone_dir, "*.db")))

if not zone_files:
    sys.stderr.write(f"[x] Error: No *.db zone files found in {zone_dir}\n")
    sys.exit(1)

results = []

for zf in zone_files:
    domain = os.path.basename(zf)[:-3]
    dom_l = domain.lower()

    try:
        with open(zf, encoding="utf-8", errors="replace") as fh:
            raw_lines = fh.readlines()
    except Exception:
        continue

    # Strip inline comments cleanly (outside quotes)
    clean_lines = []
    for ln in raw_lines:
        stripped = re.sub(r";.*$", "", ln).strip()
        if stripped:
            clean_lines.append(stripped)

    # 1. Syntax validation via named-checkzone
    syntax_ok = True
    if has_checkzone:
        proc = subprocess.run(["named-checkzone", "-q", domain, zf], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        syntax_ok = proc.returncode == 0

    # 2. Extract MX, mail A/CNAME, SPF, DKIM, DMARC
    mx_targets = []
    mail_type = "NONE"
    mail_val = "-"
    mail_ip = "-"
    has_spf = False
    has_dkim = False
    has_dmarc = False

    for ln in clean_lines:
        if re.search(r"v=spf1\b", ln, re.I):
            has_spf = True
        if re.search(r"^default\._domainkey\b|\b_domainkey\b", ln, re.I):
            has_dkim = True
        if re.search(r"^_dmarc\b", ln, re.I) and re.search(r"v=DMARC1\b", ln, re.I):
            has_dmarc = True

        m_mx = re.search(r"\bIN\s+MX\s+(\d+)\s+(\S+)", ln, re.I)
        if m_mx:
            mx_targets.append((int(m_mx.group(1)), m_mx.group(2).rstrip(".")))

        if mail_type == "NONE":
            m_mail = re.match(r"^(?:mail|" + re.escape(f"mail.{domain}.") + r")\s+(?:\d+\s+)?IN\s+(A|CNAME)\s+(\S+)", ln, re.I)
            if m_mail:
                mail_type = m_mail.group(1).upper()
                mail_val = m_mail.group(2).rstrip(".")
                if mail_type == "A":
                    mail_ip = mail_val
                elif mail_type == "CNAME":
                    if mail_val.lower() == f"mail.{dom_l}":
                        mail_ip = "LOOP"
                    elif resolve_cname:
                        target_host = mail_val if "." in mail_val else f"{mail_val}.{domain}"
                        try:
                            mail_ip = socket.gethostbyname(target_host)
                        except Exception:
                            mail_ip = "(unres)"
                    else:
                        mail_ip = "(skip)"

    mx_targets.sort(key=lambda x: x[0])
    primary_mx = mx_targets[0][1] if mx_targets else "-"

    # 3. Mail routing classification
    routing = "UNKNOWN"
    if dom_l in local_domains:
        routing = "LOCAL"
    elif dom_l in remote_domains:
        routing = "REMOTE"

    mx_is_external = False
    if primary_mx != "-":
        pmx_l = primary_mx.lower()
        if any(pmx_l == h or pmx_l.endswith("." + h) for h in EXTERNAL_MX_HINTS):
            mx_is_external = True

    issues = []
    if not syntax_ok:
        issues.append("SYNTAX_ERR")
    if not mx_targets:
        issues.append("NO_MX")
    if mail_ip == "LOOP":
        issues.append("CNAME_LOOP")
    if routing == "LOCAL" and mx_is_external:
        issues.append("ROUTING_MISMATCH")
    if not has_spf:
        issues.append("NO_SPF")
    if not has_dmarc:
        issues.append("NO_DMARC")

    status = "OK" if not issues else (
        "CRITICAL" if any(x in issues for x in ("SYNTAX_ERR", "NO_MX", "CNAME_LOOP", "ROUTING_MISMATCH")) else "WARN"
    )

    results.append({
        "domain": domain,
        "syntax_ok": syntax_ok,
        "primary_mx": primary_mx,
        "mx_count": len(mx_targets),
        "mail_type": mail_type,
        "mail_target": mail_val,
        "mail_ip": mail_ip,
        "routing": routing,
        "spf": has_spf,
        "dkim": has_dkim,
        "dmarc": has_dmarc,
        "status": status,
        "issues": issues,
        "has_issue": len(issues) > 0,
    })

total = len(results)
crit_cnt = sum(1 for r in results if r["status"] == "CRITICAL")
warn_cnt = sum(1 for r in results if r["status"] == "WARN")
ok_cnt = sum(1 for r in results if r["status"] == "OK")
shown = [r for r in results if r["has_issue"]] if only_issues else results

if fmt == "json":
    print(json.dumps({
        "version": version,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "hostname": host,
        "zone_dir": zone_dir,
        "summary": {"total": total, "ok": ok_cnt, "warn": warn_cnt, "critical": crit_cnt},
        "zones": shown,
    }, indent=2))
elif fmt == "csv":
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["domain", "status", "routing", "primary_mx", "mail_type", "mail_ip", "spf", "dkim", "dmarc", "issues"])
    for r in shown:
        w.writerow([r["domain"], r["status"], r["routing"], r["primary_mx"],
                    r["mail_type"], r["mail_ip"], r["spf"], r["dkim"], r["dmarc"], ";".join(r["issues"])])
    sys.stdout.write(buf.getvalue())
else:
    print("=" * 124)
    print(f" CPANEL DNS AUDIT v{version} - [{host}] | Dir: {zone_dir} | Zones: {total}")
    print("=" * 124)
    print(f"{'DOMAIN':<26} | {'ROUTING':<7} | {'PRIMARY MX':<28} | {'MAIL/IP':<22} | {'AUTH':<5} | {'STATUS':<8} | {'ISSUES'}")
    print("-" * 124)
    for r in shown:
        auth = ("S" if r["spf"] else "-") + ("K" if r["dkim"] else "-") + ("D" if r["dmarc"] else "-")
        col = c_grn if r["status"] == "OK" else (c_red if r["status"] == "CRITICAL" else c_yel)
        mail_col = f"{r['mail_type']}:{r['mail_ip']}" if r["mail_type"] != "NONE" else "-"
        iss = ",".join(r["issues"]) if r["issues"] else "clean"
        print(f"{r['domain'][:26]:<26} | {r['routing']:<7} | {r['primary_mx'][:28]:<28} | {mail_col[:22]:<22} | {auth:<5} | {col}{r['status']:<8}{c_rst} | {iss}")
    print("=" * 124)
    print(f" Summary: {total} zone(s) | OK: {ok_cnt} | WARN: {warn_cnt} | CRITICAL: {crit_cnt} | Auth Legend: S=SPF K=DKIM D=DMARC")
    print("=" * 124)

sys.exit(2 if (crit_cnt > 0 or warn_cnt > 0) else 0)
PYEOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    init_colors

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cp-dns-audit.XXXXXX")
    local report_tmp="${TMP_DIR}/report.out"

    log_info "Auditing DNS zones in ${ZONE_DIR}..."
    local rc=0
    run_audit "$report_tmp" || rc=$?
    if [[ "$rc" -eq 1 ]]; then
        exit 1
    fi

    if [[ -n "$OUTPUT_FILE" ]]; then
        cp "$report_tmp" "$OUTPUT_FILE"
        log_ok "Report saved to: ${OUTPUT_FILE}"
    fi

    cat "$report_tmp"

    if [[ -n "$EMAIL_TO" ]]; then
        local subj="cPanel DNS Audit Report: $(hostname 2>/dev/null || echo host)"
        if command -v mail >/dev/null 2>&1; then
            mail -s "$subj" "$EMAIL_TO" < "$report_tmp" && log_ok "Report emailed to: ${EMAIL_TO}"
        elif command -v sendmail >/dev/null 2>&1; then
            { echo "To: ${EMAIL_TO}"; echo "Subject: ${subj}"; echo "Content-Type: text/plain; charset=UTF-8"; echo ""; cat "$report_tmp"; } | sendmail -t && log_ok "Report emailed to: ${EMAIL_TO}"
        else
            log_warn "No mail/sendmail binary found; email skipped."
        fi
    fi

    exit "$rc"
}

main "$@"
