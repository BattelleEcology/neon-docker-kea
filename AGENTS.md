# AGENTS.md

Guidance for coding agents working in this repository.

## What this is

An Alpine-based container image of the Kea DHCPv4 server for NEON field sites, with two additions:

1. **`kea-hook-grape.so`** (`src/`): a Kea hooks library built here. NEON's "Grape" data loggers send a Client FQDN option (81) with both the N and S flags set, which RFC 4702 forbids, so Kea drops the packet. The `buffer4_receive` callout in `src/callouts.cpp` walks the raw wire options before Kea parses them, and when N and S are both set it clears N (`&= 0xF7`) in `query->data_`. The code is authoritative: `messages.mes` says S is cleared. This hook takes no parameters.
2. **Lease publishing to Kafka** (`scripts/`): Kea's run_script hook calls `scripts/keaevent.sh` on lease events. It writes the lease state to a Kafka topic keyed by MAC with `kcat`: a JSON value on `lease4_select`/`lease4_renew`, and a tombstone on `lease4_release`/`lease4_expire`. So the topic is meant to be compacted.

## Runtime flow

`entrypoint.sh` runs as the `kea` user:

1. Writes `KAFKA_BOOTSTRAP_SERVER` and `KAFKA_TOPIC_NAME` to `/run/kea/kea-env.sh`. The run_script hook clears the environment, so `keaevent.sh` sources this file instead of reading env vars.
2. Runs `scripts/clean_leases.sh`. It republishes still-valid leases from `/kea/*.csv*` (Kea memfile lease files) to Kafka, then tombstones expired leases it finds by reading the whole topic. In that script the `expiration` and `valid_lifetime` variables hold the CSV's `valid_lifetime` and `expire` columns respectively, the reverse of their names.
3. Starts `kea-dhcp4 -c $KEA_CONFIG_FILE` (default `/usr/local/etc/kea/kea-dhcp4.conf`).

The pod needs the `NET_BIND_SERVICE` and `NET_RAW` capabilities (raw DHCP sockets). The Dockerfile sets them as file capabilities on `kea-dhcp4`.

## Config

The baked-in `kea-dhcp4.conf` is an example. Real deployments mount their own from the `flux-lc-base` repo (`bases/kea/configs/`): a main `kea-dhcp4.conf` that `<?include?>`s a per-site `kea-site-subnetoptions.conf` with `option-data` and `subnet4`. The example mirrors that config with the site section inline, so keep the two in step.

Kea 3 only accepts lease files and control sockets under its allowed directories. The Dockerfile sets `KEA_DHCP_DATA_DIR=/kea` and `KEA_CONTROL_SOCKET_DIR=/run/kea/socket` (flux-lc-base also sets them in `kea.env`). Without them, `kea-dhcp4` rejects the config.

## Build and check

There are no tests or linters. Build and validate with Docker:

```sh
docker build -t kea-test .                          # builds the hook and the runtime image
docker build --target build -t kea-build-test .     # hook compile stage only
docker run --rm --entrypoint kea-dhcp4 kea-test -t /usr/local/etc/kea/kea-dhcp4.conf   # config check; also loads both hooks
```

The Makefile needs Kea dev headers and libs (`kea-dev`, `kealib-dev` on Alpine). The Dockerfile passes `KEA_INCLUDE=/usr/include/kea KEA_LIB=/usr/lib`; the Makefile defaults point at `/usr/local`.

Log message files: `src/messages.cc`/`messages.h` and `src/messages.cpp`/`messages.hpp` are committed, generated copies of `src/messages.mes`. The build never runs `kea-msg-compiler`: `messages.o` compiles from `messages.cc`, and `log.hpp` includes `messages.hpp`. After editing `messages.mes`, regenerate with `kea-msg-compiler -d src/ src/messages.mes` (writes `.h`/`.cc`) and update the `.hpp`/`.cpp` copies to match.

## Releases and CI

The image version is the Alpine version. Both `FROM alpine:<version>` lines in the Dockerfile must use the same version; the `plan` job in `.github/workflows/docker-publish.yml` reads it with `sed` and fails if there isn't exactly one.

- Renovate (`.github/renovate.json5`) bumps Alpine and GitHub Actions and automerges once the PR build passes (`platformAutomerge: false`, because the org ruleset requires no status checks).
- Builds use `docker/github-builder` and push to GCP Artifact Registry (via WIF) and `ghcr.io/battelleecology/neon-docker-kea`. Main builds add the tag `v<alpine version>`. The `v` prefix is required, or the registry cleanup rules delete the image.
- The `tag` job then creates the repo tag `v<alpine version>` via `gh api`, skipping it if it exists. Nobody tags by hand.
- `GITHUB_TOKEN` can't create a tag on a commit that changes `.github/workflows/` (HTTP 403), so keep Alpine bumps out of PRs that change workflows.
