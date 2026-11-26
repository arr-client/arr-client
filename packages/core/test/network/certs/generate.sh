#!/usr/bin/env bash
# Recreates the certificates of the network tests (OpenSSL 3.4 or newer).
# They are test material only: the keys are public and trusted by nothing.
# After running it, put the printed fingerprints into ../certificates.dart.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

from=20250101000000Z
to=21250101000000Z

key() { openssl ecparam -name prime256v1 -genkey -noout -out "$1"; }

ca() { # file name, common name
  key "$work/$1.key"
  openssl req -x509 -new -key "$work/$1.key" -subj "/CN=$2" \
    -not_before $from -not_after $to -out "$1.pem" \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'
}

leaf() { # file name, subjectAltName, notBefore, notAfter; signed by ca
  key "$1.key"
  openssl req -new -key "$1.key" -subj "/CN=$1" -out "$work/$1.csr"
  printf '%s\n' 'basicConstraints=CA:FALSE' 'extendedKeyUsage=serverAuth' \
    "subjectAltName=$2" 'authorityKeyIdentifier=keyid' >"$work/$1.ext"
  openssl x509 -req -in "$work/$1.csr" -CA ca.pem -CAkey "$work/ca.key" \
    -set_serial "0x$(openssl rand -hex 8)" -extfile "$work/$1.ext" \
    -not_before "$3" -not_after "$4" -out "$1.pem"
}

self_signed() { # file name, subjectAltName, notBefore, notAfter
  key "$1.key"
  openssl req -x509 -new -key "$1.key" -subj "/CN=$1" \
    -not_before "$3" -not_after "$4" -out "$1.pem" \
    -addext "subjectAltName=$2"
}

local_names='IP:127.0.0.1,DNS:localhost'

ca ca 'arr-client test CA'
ca other_ca 'arr-client unrelated test CA'
leaf leaf $local_names $from $to
leaf leaf_renewed $local_names $from $to
leaf leaf_wrong_host DNS:other.test $from $to
leaf leaf_expired $local_names 20200101000000Z 20210101000000Z
self_signed self_signed $local_names $from $to
self_signed self_signed_other $local_names $from $to
# Expired and for another host: only a pin can accept it.
self_signed self_signed_stale DNS:other.test 20200101000000Z 20210101000000Z

for file in *.pem; do
  printf '%s %s\n' "$file" \
    "$(openssl x509 -in "$file" -outform der | sha256sum | cut -d' ' -f1)"
done
