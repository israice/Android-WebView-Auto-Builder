FROM ubuntu:22.04

# Install dependencies required by the build script
# The script itself downloads Java and Android SDK, so we just need the basics.
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    zip \
    tar \
    dos2unix \
    ca-certificates \
    python3 \
    python3-pip \
    openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install flask requests

WORKDIR /app
