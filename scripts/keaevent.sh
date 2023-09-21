#!/usr/bin/env bash
set -eo pipefail
# TODO set -u and set defaults
# Kea does clean the env
. /run/kea/kea-env.sh
mac=$(echo "${LEASE4_HWADDR}" | tr -d ':')
# event_timestamp=$(date "+%m-%d-%Y,%H:%M:%S")
event_timestamp=$(date +'%s')
case "$1" in
  "lease4_select" | "lease4_renew")
  msg="{\"timestamp\":${event_timestamp},\"valid_lifetime\":${LEASE4_VALID_LIFETIME},\"mac\":\"${mac}\",\"ip\":\"${LEASE4_ADDRESS}\"}"
  # Create lease msg in kafka
  echo -n "${mac}:${msg}" | kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -K: -P -zzstd
  ;;
  "lease4_release"|"lease4_expire")
    # Tombstone the lease in kafka
    echo -n "${mac}:" | kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -P -K: -Z -zzstd
  ;;
esac