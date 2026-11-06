FROM alpine:3.24.4 AS build

RUN apk add --no-cache \
        kea-dev \
        kealib-dev \
        build-base

WORKDIR /build
COPY Makefile ./
COPY src/ src/
RUN make KEA_INCLUDE=/usr/include/kea KEA_LIB=/usr/lib

FROM alpine:3.24.4
RUN apk add --upgrade --no-cache \
    kea \
    kea-hook-run-script \
    bash \
    kcat \
    jq \
    libcap-utils \
    tini \
    && setcap 'cap_net_bind_service=ep cap_net_raw=ep' /usr/sbin/kea-dhcp4 \
    && mkdir -p /run/kea \
    && chown kea:kea /run/kea
COPY kea-dhcp4.conf /usr/local/etc/kea/
COPY --from=build /build/kea-hook-grape.so /usr/lib/kea/hooks/
# Owned by root, so the kea user can't change the scripts Kea runs
COPY scripts/ /usr/share/kea/scripts/
COPY entrypoint.sh /scripts/entrypoint.sh

USER kea:kea
# Kubernetes pod will require the following capabilities in its security policy to run:
# - NET_BIND_SERVICE
# - NET_RAW

# Volume mount new configs to /usr/local/etc/kea/kea-dhcp4.conf

# SETTINGS FOR THE SCRIPTS AND CONTAINER
ENV KEA_CONFIG_FILE=/usr/local/etc/kea/kea-dhcp4.conf
# Kea 3 only accepts lease files and control sockets under these directories.
# The lease file lives on a volume at /kea, and entrypoint.sh creates the
# socket directory.
ENV KEA_DHCP_DATA_DIR=/kea \
    KEA_CONTROL_SOCKET_DIR=/run/kea/socket

# tini runs as PID 1 to forward signals to kea-dhcp4 and reap orphaned
# processes, such as the watchdog busybox timeout leaves behind in
# entrypoint.sh, which kea-dhcp4 wouldn't reap.
ENTRYPOINT ["/sbin/tini", "--", "/scripts/entrypoint.sh"]

