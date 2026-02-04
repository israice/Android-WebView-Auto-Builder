FROM ubuntu:22.04

# Install minimal dependencies - Java/SDK are downloaded by the build script
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    zip \
    tar \
    dos2unix \
    ca-certificates \
    python3 \
    python3-pip \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir flask requests gunicorn

WORKDIR /app
