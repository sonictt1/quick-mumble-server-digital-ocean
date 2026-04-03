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
        --subdomain)
            SUBDOMAIN="$2"
            shift; shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# if [[ -z "$RESERVED_IP" || -z "$DROPLET_ID" || -z "$DOMAIN" || -z "$EMAIL" || -z "$SSH_IDENTITY_FILE" || -z "$SSH_PORT" || -z "$ADMIN_USERNAME" || -z "$SUBDOMAIN" ]]; then
    echo "RESERVED_IP=$RESERVED_IP"
    echo "DROPLET_ID=$DROPLET_ID"
    echo "DOMAIN=$DOMAIN"
    echo "EMAIL=$EMAIL"
    echo "SSH_IDENTITY_FILE=$SSH_IDENTITY_FILE"
    echo "SSH_PORT=$SSH_PORT"
    echo "ADMIN_USERNAME=$ADMIN_USERNAME"
    echo "SUBDOMAIN=$SUBDOMAIN"
    echo "Usage: $0 --reserved-ip <RESERVED_IP> --droplet-id <DROPLET_ID> --domain <DOMAIN> --email <EMAIL> --ssh-identity-file <SSH_IDENTITY_FILE> --ssh-port <SSH_PORT> --admin-username <ADMIN_USERNAME> --subdomain <SUBDOMAIN>"
    # exit 1
# fi

DROPLET_IP="$RESERVED_IP"
SSH_OPTS="-i $SSH_IDENTITY_FILE -p $SSH_PORT -o StrictHostKeyChecking=no -T"

ssh $SSH_OPTS $ADMIN_USERNAME@$DROPLET_IP <<EOF
    # Make apt non-interactive for automation
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    sudo apt-get update -yq
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -yq --no-install-recommends -o Dpkg::Options::="--force-confold" certbot
    sudo systemctl stop mumble-server || true

    if sudo certbot certonly --standalone -d "$SUBDOMAIN.$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"; then
        # Grant mumble-server user read access to the cert files (certbot defaults to root-only)
        sudo chgrp -R mumble-server /etc/letsencrypt/live/ /etc/letsencrypt/archive/
        sudo chmod -R g+rX /etc/letsencrypt/live/ /etc/letsencrypt/archive/

        # Inject SSL paths into mumble config — handle both # and ; comment prefixes and plain lines
        sudo sed -i -E "s|^[[:space:]]*[#;]?[[:space:]]*sslCert=.*|sslCert=/etc/letsencrypt/live/$SUBDOMAIN.$DOMAIN/fullchain.pem|" "/etc/mumble-server.ini"
        sudo sed -i -E "s|^[[:space:]]*[#;]?[[:space:]]*sslKey=.*|sslKey=/etc/letsencrypt/live/$SUBDOMAIN.$DOMAIN/privkey.pem|" "/etc/mumble-server.ini"
    else
        echo "ERROR: certbot failed; SSL paths NOT written to mumble config. Mumble will start without SSL." >&2
    fi

    sudo systemctl start mumble-server || true

    echo "0 3 * * * root certbot renew --quiet && chgrp -R mumble-server /etc/letsencrypt/live/ /etc/letsencrypt/archive/ && chmod -R g+rX /etc/letsencrypt/live/ /etc/letsencrypt/archive/ && systemctl restart mumble-server" | sudo tee /etc/cron.d/murmur-cert-renew
EOF