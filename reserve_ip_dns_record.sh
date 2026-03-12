
# Parse user variables
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --subdomain)
            SUBDOMAIN="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Create a reserved IP and capture it directly
RAW_OUTPUT=$(doctl compute reserved-ip create --region "$REGION" --no-header | tail -n 1)

# Extract the IPv4 address robustly (scan fields for a strict IPv4 token)
RESERVED_IP=$(echo "$RAW_OUTPUT" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }')
# If extraction failed, try to strip non-digit characters and fallback to first token
if [ -z "$RESERVED_IP" ]; then
    RESERVED_IP=$(echo "$RAW_OUTPUT" | tr -d '"' | awk '{print $1}')
fi

if [ -n "$DOMAIN" ]; then
    # send doctl domain create output to stderr so workflow captures only the IP from stdout
    doctl compute domain records create "$DOMAIN" \
      --record-type A \
      --record-name "$SUBDOMAIN" \
      --record-data "$RESERVED_IP" >&2
fi
echo "$RESERVED_IP"