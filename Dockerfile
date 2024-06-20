FROM debian:bookworm-slim

LABEL org.opencontainers.image.source = "https://github.com/dataforgoodfr/d4g-s3-backup"
LABEL org.opencontainers.image.authors = "Data For Good"

RUN apt update && apt install -y s3cmd && apt clean

ADD ./entrypoint.sh /opt/entrypoint.sh

ENTRYPOINT ["/opt/entrypoint.sh"]
