#!/bin/sh
set -e
mkdir -p /run/kea/socket
chmod 750 /run/kea/socket
if [ -e /run/kea/kea-dhcp4.kea-dhcp4.pid ]; then
  rm /run/kea/kea-dhcp4.kea-dhcp4.pid
fi
# This has to be here because the kea hook script will clear env variables
cat >/run/kea/kea-env.sh <<HERE
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER}"
KAFKA_TOPIC_NAME="${KAFKA_TOPIC_NAME}"
HERE
# Syncing leases to Kafka is best effort: DHCP has to start even when Kafka is
# down or slow.
if ! timeout "${CLEAN_LEASES_TIMEOUT:-300}" /usr/share/kea/scripts/clean_leases.sh; then
  echo "clean_leases.sh failed or timed out; starting kea-dhcp4 anyway" >&2
fi
# exec, so tini passes the SIGTERM straight to kea-dhcp4 when the pod stops
exec /usr/sbin/kea-dhcp4 -c "${KEA_CONFIG_FILE}"
