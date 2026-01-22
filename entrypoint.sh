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

# Fix permissions if running as root but switching to user
# (This script runs as root by default from Docker)
if [ "$(id -u)" = "0" ]; then
    chown -R freeswitch:freeswitch /usr/local/freeswitch
    
    # If argument is freeswitch, run it as the freeswitch user
    if [ "$1" = "freeswitch" ]; then
        shift
        exec gosu freeswitch /usr/local/freeswitch/bin/freeswitch -nf -nonat "$@"
    fi
fi

exec "$@"
