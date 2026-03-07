
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

# Create a reserved IP and capture it directly
RESERVED_IP=$(doctl compute reserved-ip create --region "$REGION" --no-header | tail -n 1)

if [ -n "$DOMAIN" ]; then
    doctl compute domain records create "$DOMAIN" \
      --record-type A \
      --record-name murmur \
      --record-data "$RESERVED_IP" >&2
fi
echo "$RESERVED_IP"