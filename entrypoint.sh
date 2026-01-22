#!/bin/bash
set -e

# entrypoint.sh - FreeSWITCH Docker Entrypoint

# Default limits (can be overridden by docker --ulimit)
# FreeSWITCH needs many file descriptors
ulimit -n 65535 || true
ulimit -c unlimited || true

# Check if we need to initialize configuration
if [ ! -f /usr/local/freeswitch/conf/freeswitch.xml ]; then
    echo "Initializing configuration..."
    # If volume is empty, this logic could copy defaults, but since we copy 
    # the whole installation, conf/ usually exists. 
    # If the user mounted an empty volume over /usr/local/freeswitch/conf,
    # they are responsible for populating it.
    # We could add logic here to restore defaults if empty.
fi

# Determine if we're starting FreeSWITCH
start_freeswitch() {
    local FS_ARGS="-nf -nonat"
    
    # Add any additional arguments passed
    if [ $# -gt 0 ]; then
        FS_ARGS="$FS_ARGS $@"
    fi
    
    echo "Starting FreeSWITCH with: $FS_ARGS"
    
    if [ "$(id -u)" = "0" ]; then
        # Running as root - switch to freeswitch user
        chown -R freeswitch:freeswitch /usr/local/freeswitch
        exec gosu freeswitch /usr/local/freeswitch/bin/freeswitch $FS_ARGS
    else
        # Already running as non-root
        exec /usr/local/freeswitch/bin/freeswitch $FS_ARGS
    fi
}

# Handle command
case "$1" in
    freeswitch|"")
        # Default command or explicit freeswitch
        shift 2>/dev/null || true
        start_freeswitch "$@"
        ;;
    -*)
        # Flags passed directly (e.g., -nf -c)
        start_freeswitch "$@"
        ;;
    *)
        # Any other command - run it directly
        exec "$@"
        ;;
esac
