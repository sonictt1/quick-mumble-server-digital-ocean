# TODO: This needs to leave the dns record, optionally. We also need to add optional teardown of reserved IPs.

# if [ $# -lt 2 ]; then
# 	echo "Usage: $0 <droplet_name> <domain>"
# 	exit 1
# fi

droplet_name="$1"
domain="$2"
reserved_ip="$3"

doctl compute droplet delete "$droplet_name"

if [ -n "$reserved_ip" ]; then
	dns_record_id=$(doctl compute domain records list "$domain" --format ID,Type,Name,Data | grep "murmur" | awk '{print $1}')
	doctl compute reserved-ip delete "$reserved_ip"
	doctl compute domain records delete "$domain" "$dns_record_id"
fi
