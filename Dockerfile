# syntax=docker/dockerfile:1

# CNPG operand image: official CloudNativePG Postgres base + TimescaleDB.
# Keeps the CNPG entrypoint and UID 26 so it drops into a Cluster unchanged.

ARG PG_MAJOR=18
ARG DEBIAN_RELEASE=trixie
ARG BASE_TAG=${PG_MAJOR}-standard-${DEBIAN_RELEASE}

FROM ghcr.io/cloudnative-pg/postgresql:${BASE_TAG}

# Re-declare after FROM to make them visible in this stage.
ARG PG_MAJOR=18
ARG DEBIAN_RELEASE=trixie
ARG TIMESCALE_VERSION=2.26.4

USER root

# Install the extension and its loader, both pinned to the same version. The
# loader ships timescaledb.so, which shared_preload_libraries resolves against.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg; \
    . /etc/os-release; \
    if [ "${VERSION_CODENAME}" != "${DEBIAN_RELEASE}" ]; then \
        echo "ERROR: base image is '${VERSION_CODENAME}' but DEBIAN_RELEASE='${DEBIAN_RELEASE}'." >&2; \
        echo "       Update BASE_TAG/DEBIAN_RELEASE and the TimescaleDB ~debian suffix together." >&2; \
        exit 1; \
    fi; \
    install -d -m 0755 /usr/share/keyrings; \
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey \
        | gpg --dearmor -o /usr/share/keyrings/timescaledb.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/debian/ ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/timescaledb.list; \
    apt-get update; \
    pkg_ext="timescaledb-2-postgresql-${PG_MAJOR}"; \
    pkg_loader="timescaledb-2-loader-postgresql-${PG_MAJOR}"; \
    ver_prefix="${TIMESCALE_VERSION}~debian${VERSION_ID}"; \
    resolve_ver() { \
        apt-cache madison "$1" \
            | awk '{print $3}' \
            | grep -F "${ver_prefix}" \
            | sort -V | tail -n1; \
    }; \
    ext_ver="$(resolve_ver "${pkg_ext}")"; \
    loader_ver="$(resolve_ver "${pkg_loader}")"; \
    if [ -z "${ext_ver}" ] || [ -z "${loader_ver}" ]; then \
        echo "ERROR: no TimescaleDB package matching '${ver_prefix}' for PG ${PG_MAJOR}." >&2; \
        exit 1; \
    fi; \
    echo "Installing ${pkg_ext}=${ext_ver} and ${pkg_loader}=${loader_ver}"; \
    apt-get install -y --no-install-recommends \
        "${pkg_ext}=${ext_ver}" \
        "${pkg_loader}=${loader_ver}"; \
    apt-get purge -y --auto-remove curl gnupg; \
    rm -f /etc/apt/sources.list.d/timescaledb.list /usr/share/keyrings/timescaledb.gpg; \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Drop back to the postgres user CNPG expects.
USER 26
