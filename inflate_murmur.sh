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
       

############### I'm just putting the default ports. The more ports we commit to #############
############### repos the more default targets we give attackers, so these ##################
############### next two ports should be changed. These should not be used ##################
###############as default in a long-running, 'production' environment #######################


MUMBLE_PORT=647383

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

# Build SSH options
SSH_OPTS="-o ConnectTimeout=20 -o StrictHostKeyChecking=no"
if [ -n "$SSH_IDENTITY_FILE" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_IDENTITY_FILE"
fi

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
    echo "  Mumble Port: ${MUMBLE_PORT:-64738}"
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
    # echo "  Attempt $i/30: SSH not ready yet, waiting 5 seconds..."
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
    apt install -y mumble-server -o Dpkg::Options::="--force-confold"
    mkdir -p /etc/mumble-server
    mkdir -p /var/lib/mumble-server
    mkdir -p /var/log/mumble-server
    chown -R mumble-server:mumble-server /var/lib/mumble-server
    chown -R mumble-server:mumble-server /var/log/mumble-server
    systemctl stop mumble-server
    
    cp /tmp/mumble-server.ini /etc/mumble-server.ini
    ls /tmp/
    chown mumble-server /etc/mumble-server/mumble-server.ini
    chmod 644 /etc/mumble-server/mumble-server.ini
    ls /etc/mumble-server/
    sed -i "s/^port=.*/port=$MUMBLE_PORT/" /etc/mumble-server.ini
    systemctl start mumble-server
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
        mkdir -p "$DB_DESTINATION_PATH"
        cp -f /tmp/mumble-server.sqlite "$DB_DESTINATION_PATH/mumble-server.sqlite"
        chown mumble-server "$DB_DESTINATION_PATH/mumble-server.sqlite"
        chmod 644 "$DB_DESTINATION_PATH/mumble-server.sqlite"
        rm /tmp/mumble-server.sqlite
EOF
fi
    # echo "Database uploaded, ini file updated, and Murmur restarted!"

ssh $SSH_OPTS root@$DROPLET_IP <<EOF
    # Configure SSH
    grep -q "^Port " /etc/ssh/sshd_config && \
    sed -i "s/^Port .*/Port $ssh_port/" /etc/ssh/sshd_config || \
    echo "Port $ssh_port" >> /etc/ssh/sshd_config
    
    # Flush existing rules
    iptables -F

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT

    # Allow established/related connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow SSH on specified port
    iptables -A INPUT -p tcp --dport $ssh_port -j ACCEPT
    
    # Allow HTTP and HTTPS for Certbot
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # Allow Mumble (TCP and UDP on specified port)
    iptables -A INPUT -p tcp --dport $MUMBLE_PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $MUMBLE_PORT -j ACCEPT

    # Drop all other incoming traffic
    iptables -A INPUT -j DROP

    # Add admin user and disable root login
    adduser --disabled-password --gecos "" $ADMIN_NAME
    usermod -aG sudo $ADMIN_NAME

    mkdir -p /home/$ADMIN_NAME/.ssh
    cp /root/.ssh/authorized_keys /home/$ADMIN_NAME/.ssh/authorized_keys
    chown -R $ADMIN_NAME:$ADMIN_NAME /home/$ADMIN_NAME/.ssh
    chmod 700 /home/$ADMIN_NAME/.ssh
    chmod 600 /home/$ADMIN_NAME/.ssh/authorized_keys

    # Enable passwordless sudo for admin account
    echo "$ADMIN_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$ADMIN_NAME
    chmod 440 /etc/sudoers.d/$ADMIN_NAME

    sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart ssh
EOF

# echo "Admin user created and root login disabled successfully."

SSH_OPTS="$SSH_OPTS -p $ssh_port"

# echo "Your Murmur server will be available at: $DROPLET_IP:$MUMBLE_PORT"

# Schedule a system restart to complete setup
ssh $SSH_OPTS -p $ssh_port $ADMIN_NAME@$DROPLET_IP "sudo reboot now"

# echo "Server Rebooting"

# Print droplet ID as the final, machine-parseable output so callers
# (for example CI workflows) can capture it reliably.
echo "$DROPLET_ID"

