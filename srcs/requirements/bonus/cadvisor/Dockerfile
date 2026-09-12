FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN wget -O /usr/local/bin/cadvisor https://github.com/google/cadvisor/releases/download/v0.49.1/cadvisor-v0.49.1-linux-amd64 && \
    chmod +x /usr/local/bin/cadvisor

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/cadvisor", "--port=8080"]