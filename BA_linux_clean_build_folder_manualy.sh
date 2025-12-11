#!/bin/bash
WORK_DIR="$(pwd)/android_build_env"

if [ -d "$WORK_DIR" ]; then
    echo "Checking for lingering processes..."
    # Kill any processes running from this directory (e.g., Gradle Daemon)
    pkill -f "$WORK_DIR" || true
    sleep 2

    echo "Removing $WORK_DIR..."
    rm -rf "$WORK_DIR"
    echo "Cleanup complete."
else
    echo "Nothing to clean. '$WORK_DIR' does not exist."
fi
