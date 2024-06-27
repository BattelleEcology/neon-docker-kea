FROM alpine:3.20.1 as build

RUN apk add --update --upgrade --no-cache \
        curl \
        git \
        wget \
        kea-dev \
        make \
        build-base \
        binutils \
      && mkdir -p /build/src

COPY Makefile /build/
COPY src/ /build/src/
RUN ls -la /build/src
RUN cd /build \
    && make KEA_MSG_COMPILER=/usr/bin/kea-msg-compiler KEA_INCLUDE=/usr/include/kea KEA_LIB=/usr/lib 

FROM alpine:3.20.1
RUN apk add --update --upgrade --no-cache \
    kea \
    kea-hook-run-script \
    bash \
    kafkacat \
    jq \
    libcap-utils \
    && setcap 'cap_net_bind_service=ep cap_net_raw=ep' /usr/sbin/kea-dhcp4 \
    && rm -rf /var/cache/apk/* \
    && mkdir -p /run/kea \
    && chown kea:kea /run/kea \
    && mkdir /scripts
COPY ./kea-dhcp4.conf /usr/local/etc/kea/
COPY --from=build /build/kea-hook-grape.so /usr/lib/kea/hooks/
COPY scripts /scripts/

USER kea:kea
# Kubernetes pod will require the following capabilities in it's security policy to run:
# - NET_BIND_SERVICE
# - NET_RAW

# Volume mount new configs to /usr/local/etc/kea/kea-dhcp4.conf

# SETTINGS FOR THE SCRIPTS AND CONTAINER
ENV KEA_CONFIG_FILE=/usr/local/etc/kea/kea-dhcp4.conf

ENTRYPOINT ["/scripts/entrypoint.sh"]

