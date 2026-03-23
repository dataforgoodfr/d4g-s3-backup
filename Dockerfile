FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/dataforgoodfr/d4g-s3-backup"
LABEL org.opencontainers.image.authors="Data For Good France"

RUN apt update && apt install -y s3cmd rsync curl && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list && \
    apt update && apt install -y gum && \
    apt clean && rm -rf /var/lib/apt/lists/*

ADD ./entrypoint.sh /opt/entrypoint.sh
ADD ./restore.sh /opt/restore.sh
RUN chmod +x /opt/restore.sh

ENTRYPOINT ["/opt/entrypoint.sh"]
