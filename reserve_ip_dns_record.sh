
# Parse user variables
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
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

# Create a reserved IP and capture the raw output
RAW_OUTPUT=$(doctl compute reserved-ip create --region "$REGION" --no-header | tail -n 1)
# Extract the first IPv4 address from the output (works for either a plain IP or a detailed record line)
RESERVED_IP=$(echo "$RAW_OUTPUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
# Fallback to raw output if no IP found
if [ -z "$RESERVED_IP" ]; then
    RESERVED_IP="$RAW_OUTPUT"
fi

if [ -n "$DOMAIN" ]; then
    doctl compute domain records create "$DOMAIN" \
      --record-type A \
      --record-name murmur \
      --record-data "$RESERVED_IP"
fi
echo "$RESERVED_IP"