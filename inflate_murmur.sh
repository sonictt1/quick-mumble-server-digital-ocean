#! /bin/bash

# Function to display usage
usage() {
    # echo "  --mumble-ini <file>       Path to mumble-server.ini file (optional)"
    # echo "Usage: $0 [OPTIONS]"
    # echo ""
    # echo "Options:"
    # echo "  -n, --name <name>         Droplet name (default: murmur-server)"
    # echo "  -i, --image <image>       Droplet image (default: ubuntu-22-04-x64)"
    # echo "  -s, --size <size>         Droplet size (default: s-1vcpu-1gb)"
    # echo "  -r, --region <region>     Droplet region (default: nyc1)"
    # echo "  -k, --ssh-key <key-id>    SSH key ID (required)"
    # echo "  -x, --identity <file>     SSH identity file (optional)"
    # echo "  -o, --ssh-port <port>     SSH port (default: 22)"
    # echo "  -d, --database <file>     SQLite database file to upload (optional)"
    # echo "  -p, --project-id <project>   Project ID to assign the droplet to (required)"
    # echo "  -m, --domain <domain>     Domain name managed by DigitalOcean. Creates 'murmur.' subdomain (optional)"
    # echo "  -e, --email <email>       Email address for Let's Encrypt SSL certificate (required for SSL)"
    # echo "  -l, --mumble-port <port>  Mumble server port (default: 64738)"
    # echo "  -t, --tags <tags>         Additional comma-separated tags to append to droplet (optional)"
        # echo "  --reserved-ip <ip>        Reserved IP to assign to droplet (optional)"
    # echo "  -a, --admin <name>        Admin account name (default: admin)"
    # echo "  -v, --verbose             Enable verbose output (optional)"
    # echo "  -h, --help                Show this help message"
    # echo ""
    # echo "Examples:"
    # echo "  $0 --ssh-key 12345678"
    # echo "  $0 -k 12345678 -n my-server -r sfo3 -s s-2vcpu-2gb"
    # echo "  $0 -k 12345678 -d ./my-server.sqlite"
    # echo "  $0 -k 12345678 -x ~/.ssh/id_ed25519 -d ./backup.sqlite"
    # echo "  $0 -k 12345678 -m example.com -e user@example.com -o 2222 -t custom1,custom2 -a myadmin -v"
    exit 1
}

# Default values
DROPLET_NAME="murmur-server"
IMAGE="ubuntu-22-04-x64"
SIZE="s-1vcpu-1gb"
REGION="nyc1"
SSH_KEY_ID=""
SSH_IDENTITY_FILE=""
ssh_port=22
DATABASE_FILE=""
DOMAIN=""
VERBOSE=0
TAG_APPEND=""
ADMIN_NAME="admin"
RESERVED_IP=""
MUMBLE_INI_FILE=""
PUBLIC_KEY=""

# Default Mumble server port (can be overridden with -l/--mumble-port)
MUMBLE_PORT=64738
       

############### I'm just putting the default ports. The more ports we commit to #############
############### repos the more default targets we give attackers, so these ##################
############### next two ports should be changed. These should not be used ##################
###############as default in a long-running, 'production' environment #######################


# MUMBLE_PORT=64738

# Internal configuration variables
DB_DESTINATION_PATH="/var/lib/mumble-server"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            DROPLET_NAME="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -s|--size)
            SIZE="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY_ID="$2"
            shift 2
            ;;
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -x|--identity)
            SSH_IDENTITY_FILE="$2"
            shift 2
            ;;
        --ssh-public-key)
            PUBLIC_KEY="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE_FILE="$2"
            shift 2
            ;;
        -m|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -o|--ssh-port)
            ssh_port="$2"
            shift 2
            ;;
        -l|--mumble-port)
            MUMBLE_PORT="$2"
            shift 2
            ;;
        -t|--tags)
            TAG_APPEND="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        -a|--admin)
            ADMIN_NAME="$2"
            shift 2
            ;;
        --reserved-ip)
            RESERVED_IP="$2"
            shift 2
            ;;
         --mumble-ini)
            MUMBLE_INI_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check required parameters
if [ -z "$SSH_KEY_ID" ]; then
    echo "Error: SSH key ID is required!"
    echo "Use 'doctl compute ssh-key list' to get your SSH key ID"
    echo ""
    usage
fi

# Check if database file exists (if provided)
if [ -n "$DATABASE_FILE" ] && [ ! -f "$DATABASE_FILE" ]; then
    echo "Error: Database file '$DATABASE_FILE' not found!"
    exit 1
fi

# Check if SSH identity file exists (if provided)
if [ -n "$SSH_IDENTITY_FILE" ] && [ ! -f "$SSH_IDENTITY_FILE" ]; then
    echo "Error: SSH identity file '$SSH_IDENTITY_FILE' not found!"
    exit 1
fi

# Build SSH options (single set — always port 22)
SSH_OPTS="-o ConnectTimeout=20 -o StrictHostKeyChecking=no -p 22"
if [ -n "$SSH_IDENTITY_FILE" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_IDENTITY_FILE"
fi
SETUP_SSH_OPTS="$SSH_OPTS"

if [ "$VERBOSE" -eq 1 ]; then
    echo "[VERBOSE] Creating Murmur server droplet with the following configuration:"
    echo "  Name: $DROPLET_NAME"
    echo "  Image: $IMAGE"
    echo "  Size: $SIZE"
    echo "  Region: $REGION"
    echo "  SSH Key ID: $SSH_KEY_ID"
    echo "  SSH Identity: ${SSH_IDENTITY_FILE:-default}"
    echo "  Database file: ${DATABASE_FILE:-none (will create new)}"
    echo "  Email: ${EMAIL:-none (required for SSL)}"
    echo "  Project ID: ${PROJECT_ID:-none (required for project association)}"
    echo "  Mumble Port: ${MUMBLE_PORT}"
    echo "  SSH Port: ${ssh_port:-22}"
    echo "  Tags To Append: ${TAG_APPEND:-'<none>'}"
    echo "  Admin Account name: ${ADMIN_NAME:-admin}"
    echo "  Domain: ${DOMAIN:-none (required for SSL)}"
    echo "  Mumble INI File: ${MUMBLE_INI_FILE}"
    echo "  Verbose: enabled"
    echo ""
else
    echo "Mumble voice chat server creation starting... This might take several minutes."
fi

# Create a Murmur server droplet
# If an IP is provided, use provided IP. Otherwise create without reserved IP

DROPLET_IP=$(doctl compute droplet create "$DROPLET_NAME" \
        --image "$IMAGE" \
        --size "$SIZE" \
        --region "$REGION" \
        --ssh-keys "$SSH_KEY_ID" \
        --tag-names "murmur-server,created-$(date +%Y-%m-%d),ssh-key-$SSH_KEY_ID,cloud-init,auto-deployed${DOMAIN:+,domain-$DOMAIN}${TAG_APPEND:+,$TAG_APPEND}" \
        --wait \
        --format PublicIPv4 \
        --no-header)

DROPLET_ID=$(doctl compute droplet get $DROPLET_NAME --format ID --no-header | tail -n 1)


if [ -z "$DROPLET_ID" ]; then
    echo "Error: Failed to retrieve droplet ID!"
    exit 1
fi

if [ -n "$RESERVED_IP" ]; then
    doctl compute reserved-ip-action assign $RESERVED_IP $DROPLET_ID
    DROPLET_IP=$RESERVED_IP
fi


# if [ "$VERBOSE" -eq 1 ]; then
#     # echo "[VERBOSE] Droplet IP before script sleeps: $DROPLET_IP"
#     # echo "[VERBOSE] Adding droplet to project: $PROJECT_ID"
# fi

# Assign droplet to project if `PROJECT_ID` was provided
if [ -n "${PROJECT_ID:-}" ]; then
    doctl projects resources assign "$PROJECT_ID" --resource "do:droplet:$DROPLET_ID" > /dev/null
else
    echo "PROJECT_ID not set; skipping project assignment"
fi
# Wait for SSH to be ready (up to 5 minutes)
for i in {1..30}; do
    if ssh $SSH_OPTS root@$DROPLET_IP "echo 'SSH ready'" 2>/dev/null; then
        break
    fi
    sleep 5
done

# echo "Murmur server droplet created successfully!"

# Upload and install the conf file
# if [ -n "$MUMBLE_INI_FILE" ]; then
    scp $SSH_OPTS "$MUMBLE_INI_FILE" root@$DROPLET_IP:/tmp/mumble-server.ini
# fi
    
# echo "Installing database and restarting Murmur..."
ssh $SSH_OPTS root@$DROPLET_IP << EOF
    apt update -y -o Dpkg::Options::="--force-confold"
    UCF_FORCE_CONFFOLD=1 apt upgrade -y -o Dpkg::Options::="--force-confold"
    # Ensure universe repository is enabled (mumble-server may live in universe)
    apt-get install -y software-properties-common || true
    add-apt-repository -y universe || true
    apt update -y
    apt install -y mumble-server -o Dpkg::Options::="--force-confold" || true

    mkdir -p /var/lib/mumble-server
    mkdir -p /var/log/mumble-server

    # Ensure mumble-server system user exists before chown
    if ! id -u mumble-server >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin mumble-server || true
    fi

    chown -R mumble-server:mumble-server /var/lib/mumble-server || true
    chown -R mumble-server:mumble-server /var/log/mumble-server || true
    systemctl stop mumble-server || true

    # Ubuntu mumble-server package expects config at /etc/mumble-server.ini (not a subdirectory)
    cp /tmp/mumble-server.ini /etc/mumble-server.ini
    chown mumble-server /etc/mumble-server.ini || true
    chmod 640 /etc/mumble-server.ini || true
    sed -i "s/^port=.*/port=$MUMBLE_PORT/" /etc/mumble-server.ini || true
    # Do NOT start the service here; wait until DB (and any WAL/SHM sidecars) are in place
    rm /tmp/mumble-server.ini
EOF

# Upload database file if provided
if [ -n "$DATABASE_FILE" ]; then
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[VERBOSE] Uploading database file..."
        echo "[VERBOSE] Waiting for SSH to be available..."
        echo "[VERBOSE] Using SSH options: $SSH_OPTS"
        echo "[VERBOSE] Full ssh command: ssh $SSH_OPTS root@$DROPLET_IP"
    fi
    scp $SSH_OPTS "$DATABASE_FILE" root@$DROPLET_IP:/tmp/mumble-server.sqlite

    ssh $SSH_OPTS root@$DROPLET_IP << EOF
        # Stop the service before replacing the DB to avoid file-descriptor issues
        systemctl stop mumble-server || true

        mkdir -p "$DB_DESTINATION_PATH"
        # Copy main DB and any WAL/SHM sidecars if present
        for f in /tmp/mumble-server.sqlite*; do
            if [ -e "\$f" ]; then
                cp -f "\$f" "$DB_DESTINATION_PATH/\$(basename "\$f")"
            fi
        done

        chown mumble-server:mumble-server "$DB_DESTINATION_PATH"/mumble-server.sqlite* || true
        chmod 660 "$DB_DESTINATION_PATH"/mumble-server.sqlite* || true

        # Ensure WAL content is checkpointed into the main DB so murmur sees latest state
        if command -v sqlite3 >/dev/null 2>&1; then
            sudo -u mumble-server sqlite3 "$DB_DESTINATION_PATH/mumble-server.sqlite" 'PRAGMA wal_checkpoint(FULL);' || true
        fi

        # Clean up temporary uploads
        rm -f /tmp/mumble-server.sqlite*

        # Start the service after the DB is in place
        systemctl start mumble-server || true
EOF
fi
    # echo "Database uploaded, ini file updated, and Murmur restarted!"

ssh $SSH_OPTS root@$DROPLET_IP <<EOF
    # Add admin user (create home) and add to sudoers (idempotent)
    if ! id -u "$ADMIN_NAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$ADMIN_NAME" || true
    fi
    usermod -aG sudo "$ADMIN_NAME" || true

    mkdir -p /home/"$ADMIN_NAME"/.ssh

    # Provision admin's authorized_keys: prefer provided public key, else copy existing keys on droplet
    if [ -n "${PUBLIC_KEY:-}" ]; then
        cat > /home/$ADMIN_NAME/.ssh/authorized_keys <<PUBKEY
${PUBLIC_KEY}
PUBKEY
    else
        if [ -f /root/.ssh/authorized_keys ]; then
            cp /root/.ssh/authorized_keys /home/$ADMIN_NAME/.ssh/authorized_keys
        elif [ -f /home/ubuntu/.ssh/authorized_keys ]; then
            cp /home/ubuntu/.ssh/authorized_keys /home/$ADMIN_NAME/.ssh/authorized_keys
        elif [ -f /home/debian/.ssh/authorized_keys ]; then
            cp /home/debian/.ssh/authorized_keys /home/$ADMIN_NAME/.ssh/authorized_keys
        else
            touch /home/$ADMIN_NAME/.ssh/authorized_keys
        fi
    fi

    chown -R $ADMIN_NAME:$ADMIN_NAME /home/$ADMIN_NAME/.ssh
    chmod 700 /home/$ADMIN_NAME/.ssh
    chmod 600 /home/$ADMIN_NAME/.ssh/authorized_keys

    # Enable passwordless sudo for admin account
    echo "$ADMIN_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$ADMIN_NAME
    chmod 440 /etc/sudoers.d/$ADMIN_NAME

    # Disable root login now that admin user has authorized_keys
    if grep -q "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
    else
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    fi
    systemctl restart ssh || true

    # Configure firewall with UFW (persists through reboots on Ubuntu)
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow $MUMBLE_PORT/tcp
    ufw allow $MUMBLE_PORT/udp
    ufw --force enable

    # Final sync and reboot to apply all changes
    sync
    reboot now
EOF

# Wait for the server to come back up after reboot (port 22, admin user).
sleep 20
for i in {1..40}; do
    if ssh $SSH_OPTS "$ADMIN_NAME@$DROPLET_IP" "echo 'SSH ready post-reboot'" 2>/dev/null; then
        break
    fi
    sleep 5
done

# Print droplet ID as the final, machine-parseable output so callers
# (for example CI workflows) can capture it reliably.
echo "$DROPLET_ID"

# (authorized_keys already provisioned during remote setup block)

