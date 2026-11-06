#!/usr/bin/env bash
# Called by Kea's run_script hook on lease events. Publishes the lease state
# to a compacted Kafka topic keyed by MAC: a JSON value for an active lease, a
# tombstone when the lease ends.
set -eo pipefail
# The run_script hook clears the environment, so the Kafka settings come from
# the file entrypoint.sh writes.
. /run/kea/kea-env.sh

publish() { # mac cltt valid_lifetime ip
  [ -n "$1" ] || return 0
  msg="{\"timestamp\":$2,\"valid_lifetime\":$3,\"mac\":\"$1\",\"ip\":\"$4\"}"
  echo -n "$1:${msg}" | kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -K: -P -zzstd
}

tombstone() { # mac
  [ -n "$1" ] || return 0
  echo -n "$1:" | kcat -b "${KAFKA_BOOTSTRAP_SERVER}" -t "${KAFKA_TOPIC_NAME}" -P -K: -Z -zzstd
}

case "$1" in
  "leases4_committed")
    # Called after every DHCPREQUEST, with the leases it granted or renewed.
    # Leases it deleted (DELETED_LEASES4_*) are ignored: the topic is keyed by
    # MAC, so the client's new lease replaces the old one.
    for ((i = 0; i < ${LEASES4_SIZE:-0}; i++)); do
      lease="LEASES4_AT${i}"
      addr="${lease}_ADDRESS" hwaddr="${lease}_HWADDR" cltt="${lease}_CLTT" lft="${lease}_VALID_LIFETIME"
      publish "${!hwaddr//:/}" "${!cltt}" "${!lft}" "${!addr}"
    done
    ;;
  "lease4_renew")
    # Renewals also reach leases4_committed; this is a harmless duplicate.
    publish "${LEASE4_HWADDR//:/}" "${LEASE4_CLTT:-$(date +'%s')}" "${LEASE4_VALID_LIFETIME}" "${LEASE4_ADDRESS}"
    ;;
  "lease4_release" | "lease4_expire" | "lease4_decline")
    tombstone "${LEASE4_HWADDR//:/}"
    ;;
esac
