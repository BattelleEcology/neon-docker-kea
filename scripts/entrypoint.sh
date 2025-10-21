#!/bin/sh
set -e
chmod 750 /run/kea
if [ -e /run/kea/kea-dhcp4.kea-dhcp4.pid ]; then
  rm /run/kea/kea-dhcp4.kea-dhcp4.pid
fi
# This has to be here because the kea hook script will clear env variables
cat >/run/kea/kea-env.sh <<HERE
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER}"
KAFKA_TOPIC_NAME="${KAFKA_TOPIC_NAME}"
HERE
/scripts/clean_leases.sh
/usr/sbin/kea-dhcp4 -c "${KEA_CONFIG_FILE}"
