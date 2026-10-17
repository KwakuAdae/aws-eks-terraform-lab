#!/usr/bin/env bash
# Generate CPU load from inside the cluster and watch the HorizontalPodAutoscaler react.
source "$(dirname "$0")/config.sh"
SECS="${1:-180}"

step "Starting 3 load generators for ${SECS}s"
for i in 1 2 3; do
  kubectl run "load-${i}" -n website --image=busybox:1.36 --restart=Never --quiet -- \
    /bin/sh -c "end=\$((\$(date +%s)+${SECS})); while [ \$(date +%s) -lt \$end ]; do wget -q -O- http://website >/dev/null; done" \
    >/dev/null 2>&1 || true
done
kubectl get hpa website -n website -w &
WATCH=$!
sleep "$SECS"
kill "$WATCH" 2>/dev/null || true
kubectl delete pod -n website load-1 load-2 load-3 --ignore-not-found >/dev/null
echo "Load stopped. The HPA scales back down after about 5 minutes."
