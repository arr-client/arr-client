#!/bin/sh
# Run by the nginx image before it starts. The certificate lives in a volume, so its fingerprint
# stays the same until `down -v` (or until the files are removed), which is how to test a changed
# certificate. The key never leaves the volume.
set -eu

if [ ! -f /certs/server.crt ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
        -subj "/CN=arr-client devstack" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.0.2.2" \
        -keyout /certs/server.key -out /certs/server.crt
fi
