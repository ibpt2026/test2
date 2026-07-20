#!/usr/bin/env bash
set +e
C="IBPT-RUNNER-CANARY-8842"; CACHE=/ib-workspace/cache
echo "### $C recon4 start $(date -u +%FT%TZ) run=$GITHUB_RUN_ID sha=$GITHUB_SHA ref=$GITHUB_REF"
echo "==== IB accelerator logs (cache save/restore mechanism) ===="
for f in "$CACHE"/log/*.log; do echo "----- $f -----"; tail -c 3000 "$f" 2>/dev/null; echo; done
echo "==== last_runs.txt (accumulates across runs?) ===="; cat "$CACHE/last_runs.txt" 2>/dev/null
echo "==== how is the managed cache keyed? grep configs for key/branch/ref/repo/hash ===="
sudo grep -rsanE 'cache[_-]?key|restore|s3|bucket|branch|ref|repo|scope|namespace' /opt/incredibuild/management /ib-workspace/incredibuild 2>/dev/null | grep -ivE 'terminfo|licenses' | head -40
echo "==== ccache/sccache config + stats BEFORE build ===="
ccache -p 2>/dev/null | head; ccache -s 2>/dev/null | head -20; echo "--sccache--"; sccache --show-stats 2>/dev/null | head -20
echo "==== BUILD via IB-accelerated shims (verbose) ===="
export CCACHE_LOGFILE=/tmp/ccache.log
which make; type make
make clean >/dev/null 2>&1
IB_DEBUG=1 IB_VERBOSE=1 make -j all 2>&1 | tail -c 3000
echo "==== ccache/sccache stats AFTER build (hits? saved?) ===="
ccache -s 2>/dev/null | head -20; echo "--sccache--"; sccache --show-stats 2>/dev/null | head -20
echo "--ccache log tail--"; tail -c 1500 /tmp/ccache.log 2>/dev/null
echo "==== any process/step that uploads cache to S3 at job end? ===="
sudo grep -rsanE 'save.?cache|upload|put.?object|presign|vnext-data|build-monitor' /opt/incredibuild/management 2>/dev/null | head -20
echo "### $C recon4 end $(date -u +%FT%TZ)"
