FROM ubuntu:22.04

# OCI image labels
LABEL org.opencontainers.image.source="https://github.com/israice/Android-WebView-Auto-Builder"
LABEL org.opencontainers.image.description="Android WebView APK Builder - Convert URLs to Android apps in under 1 second"
LABEL org.opencontainers.image.licenses="MIT"

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

# Create non-root user for security
RUN useradd -m -u 1000 -s /bin/bash appuser

WORKDIR /app

# Set ownership
RUN mkdir -p /app && chown -R appuser:appuser /app

# Expose default port
EXPOSE 5000

# Switch to non-root user
USER appuser

# Git safe directory config (must be after USER switch)
RUN git config --global --add safe.directory /app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:5000/ || exit 1
