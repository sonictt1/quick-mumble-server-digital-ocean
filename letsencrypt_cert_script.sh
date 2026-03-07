#!/bin/bash

# Usage: ./letsencrypt_cert_script.sh --reserved-ip <RESERVED_IP> --droplet-id <DROPLET_ID> --domain <DOMAIN> --email <EMAIL> --ssh-identity-file <SSH_IDENTITY_FILE> --ssh-port <SSH_PORT>

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --reserved-ip)
            RESERVED_IP="$2"
            shift; shift
            ;;
        --droplet-id)
            DROPLET_ID="$2"
            shift; shift
            ;;
        --domain)
            DOMAIN="$2"
            shift; shift
            ;;
        --email)
            EMAIL="$2"
            shift; shift
            ;;
        --ssh-identity-file)
            SSH_IDENTITY_FILE="$2"
            shift; shift
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift; shift
            ;;
        --admin-username)
            ADMIN_USERNAME="$2"
            shift; shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$RESERVED_IP" || -z "$DROPLET_ID" || -z "$DOMAIN" || -z "$EMAIL" || -z "$SSH_PORT" ]]; then
    echo "RESERVED_IP=$RESERVED_IP"
    echo "DROPLET_ID=$DROPLET_ID"
    echo "DOMAIN=$DOMAIN"
    echo "EMAIL=$EMAIL"
    echo "SSH_IDENTITY_FILE=${SSH_IDENTITY_FILE:-<none>}"
    echo "SSH_PORT=$SSH_PORT"
    echo "Usage: $0 --reserved-ip <RESERVED_IP> --droplet-id <DROPLET_ID> --domain <DOMAIN> --email <EMAIL> [--ssh-identity-file <SSH_IDENTITY_FILE>] --ssh-port <SSH_PORT>"
    exit 1
fi

DROPLET_IP="$RESERVED_IP"
# Prefer SSH agent; only add identity file option if provided
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no"
if [ -n "${SSH_IDENTITY_FILE:-}" ]; then
    SSH_OPTS="-i $SSH_IDENTITY_FILE $SSH_OPTS"
fi

ssh $SSH_OPTS $ADMIN_USERNAME@$DROPLET_IP <<EOF
    sudo apt install -yq certbot
    sudo systemctl stop mumble-server

    sudo certbot certonly --standalone -d "mumble.$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"

    sudo sed -i "/^sslCert=/c\\sslCert=/etc/letsencrypt/live/mumble.$DOMAIN/fullchain.pem" "/etc/mumble-server.ini"
    sudo sed -i "/^sslKey=/c\\sslKey=/etc/letsencrypt/live/mumble.$DOMAIN/privkey.pem" "/etc/mumble-server.ini"

    sudo systemctl start mumble-server

    echo "0 3 * * * root certbot renew --quiet && sudo systemctl restart mumble-server" | sudo tee /etc/cron.d/murmur-cert-renew
EOF