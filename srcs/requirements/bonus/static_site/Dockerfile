FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 && \
    rm -rf /var/lib/apt/lists/*

COPY src /var/www/html

WORKDIR /var/www/html
EXPOSE 3000
ENTRYPOINT ["python3", "-m", "http.server", "3000"]