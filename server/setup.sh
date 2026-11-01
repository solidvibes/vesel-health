#!/bin/bash
# Makes the certificate, the token and the phone's set-up QR code for the Vesel backup server.
# Usage: server/setup.sh [--force | --qr-text]
#   --force    replace an existing certificate and token (the phone must scan the new QR).
#   --qr-text  for the Vesel Backup app: keep the certificate if there is one, make a new token,
#              print only the QR text on stdout. Needs only openssl and shasum.
# Env: VESEL_SERVER_HOME (data folder), VESEL_SERVER_HOST (name in the certificate and QR).
set -euo pipefail

force=0
qr_text=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        --qr-text) qr_text=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
if [[ $force -eq 1 && $qr_text -eq 1 ]]; then
    echo "Use --force or --qr-text, not both." >&2
    exit 2
fi

server_dir="$(cd "$(dirname "$0")" && pwd)"
data="${VESEL_SERVER_HOME:-$HOME/Library/Application Support/vesel-server}"
host="${VESEL_SERVER_HOST:-$(scutil --get LocalHostName).local}"
port=8443

tools=(qrencode uv openssl shasum)
if [[ $qr_text -eq 1 ]]; then
    tools=(openssl shasum)
fi
for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        case "$tool" in
            qrencode) echo "qrencode is missing. Install it with: brew install qrencode" >&2 ;;
            uv) echo "uv is missing. Install it with: brew install uv" >&2 ;;
            *) echo "$tool is missing." >&2 ;;
        esac
        exit 1
    fi
done

certs="$data/certs"
if [[ $force -eq 0 && $qr_text -eq 0 && ( -e "$certs/cert.pem" || -e "$certs/key.pem" || -e "$data/token.sha256" ) ]]; then
    echo "A certificate or token already exists in $data." >&2
    echo "Run again with --force to replace them; the phone then has to scan the new QR." >&2
    exit 1
fi

umask 077
mkdir -p "$certs"
chmod 700 "$data" "$certs"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $host
[ext]
subjectAltName = DNS:$host
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
EOF

keep_cert=0
if [[ $qr_text -eq 1 && -f "$certs/cert.pem" && -f "$certs/key.pem" ]]; then
    keep_cert=1
    cp "$certs/cert.pem" "$work/cert.pem"
else
    openssl ecparam -name prime256v1 -genkey -noout -out "$work/key.pem" 2>/dev/null
    openssl req -new -x509 -sha256 -days 3650 -key "$work/key.pem" \
        -config "$work/openssl.cnf" -out "$work/cert.pem" 2>/dev/null
fi

token="$(openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=\n')"
printf '%s' "$token" | shasum -a 256 | cut -c1-64 > "$work/token.sha256"

pin="$(openssl x509 -in "$work/cert.pem" -pubkey -noout \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary \
    | base64)"
pin_query="$(printf '%s' "$pin" | sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')"

if [[ $keep_cert -eq 0 ]]; then
    mv -f "$work/key.pem" "$certs/key.pem"
    mv -f "$work/cert.pem" "$certs/cert.pem"
fi
mv -f "$work/token.sha256" "$data/token.sha256"
chmod 600 "$certs/key.pem" "$certs/cert.pem" "$data/token.sha256"

qr="vesel-backup://$host:$port?token=$token&pin=$pin_query"
if [[ $qr_text -eq 1 ]]; then
    printf '%s\n' "$qr"
    exit 0
fi

(cd "$server_dir" && uv sync --frozen --no-dev --quiet)

uv_path="$(command -v uv)"
sed -e "s|__USER__|$(id -un)|g" \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__SERVER_DIR__|$server_dir|g" \
    -e "s|__UV__|$uv_path|g" \
    -e "s|__DATA__|$data|g" \
    "$server_dir/launchd/app.vesel.server.plist" > "$data/app.vesel.server.plist"
chmod 644 "$data/app.vesel.server.plist"

echo
echo "Scan this with Vesel on the iPhone (Loop & settings > Set up backup)."
echo "It holds the backup key: don't photograph or share it."
echo
printf '%s' "$qr" | qrencode -t ANSIUTF8
echo
echo "Server name: $host:$port"
echo "Certificate pin (SHA-256 of the public key): $pin"
echo
echo "To start the server now and at every boot, run:"
echo "  sudo cp \"$data/app.vesel.server.plist\" /Library/LaunchDaemons/"
echo "  sudo launchctl bootstrap system /Library/LaunchDaemons/app.vesel.server.plist"
