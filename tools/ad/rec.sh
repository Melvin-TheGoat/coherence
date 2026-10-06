#!/bin/bash
# rec.sh <name> <seconds> KEY=VAL ...
D=${AD_DIR:?set AD_DIR to an output folder}
S=304926AB-ABDD-4B14-9D65-E0359797D3DB
name=$1; secs=$2; shift 2
env=()
for kv in "$@"; do env+=("SIMCTL_CHILD_$kv"); done
xcrun simctl terminate $S com.azizmahmud.808 2>/dev/null
rm -f "$D/$name.mp4"
xcrun simctl io $S recordVideo --codec=h264 --force "$D/$name.mp4" >/dev/null 2>&1 &
R=$!
sleep 1.5
env "${env[@]}" SIMCTL_CHILD_SKIP_ONBOARDING=1 SIMCTL_CHILD_STORE_SHOTS=1 SIMCTL_CHILD_DEMO_NAME=Maya SIMCTL_CHILD_VALLEY_HOUR=12 xcrun simctl launch $S com.azizmahmud.808 >/dev/null
sleep "$secs"
kill -INT $R; wait $R 2>/dev/null
ls -la "$D/$name.mp4" | awk '{print $5, $9}'
