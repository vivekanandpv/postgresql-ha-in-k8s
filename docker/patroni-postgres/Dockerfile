# Patroni + PostgreSQL, built transparently from the official postgres image
# instead of pulling a large pre-built image, so every layer of the HA logic
# is visible in this repo.
FROM postgres:17-bookworm

ARG PATRONI_VERSION=3.3.6
ARG KUBECTL_VERSION=v1.31.0
# Passed explicitly by scripts/01-build-and-load-image.sh (derived from `uname -m`)
# rather than relied on as an implicit buildkit arg, so `docker build` works
# the same way whether or not buildx/buildkit is the active builder.
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        curl \
        ca-certificates \
    && pip3 install --break-system-packages --no-cache-dir \
        "patroni[etcd3]==${PATRONI_VERSION}" \
        psycopg2-binary \
    && curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && apt-get purge -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY patroni.yml /etc/patroni/patroni.yml
COPY on-role-change.sh /scripts/on-role-change.sh
RUN chmod +x /scripts/on-role-change.sh

# Patroni drives PostgreSQL directly (initdb, start, stop, promote, demote),
# so we do not reuse the postgres image's own docker-entrypoint.sh.
USER postgres
EXPOSE 5432 8008
ENTRYPOINT ["patroni", "/etc/patroni/patroni.yml"]
