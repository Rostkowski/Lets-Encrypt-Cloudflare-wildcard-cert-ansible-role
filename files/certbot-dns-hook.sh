#!/bin/sh

# Some of the code taken from 
# https://github.com/systemli/ansible-role-letsencrypt

# Script will exit if any command fails
set -e

# Sanity check: environmental variables $CERTBOT_DOMAIN and $CERTBOT_VALIDATION
# are passed by certbot and are mandatory for the script to work
# https://eff-certbot.readthedocs.io/en/stable/using.html#pre-and-post-validation-hooks
if [ -z ${CERTBOT_DOMAIN} ]; then
    echo "Error: variable \$CERTBOT_DOMAIN is unset" >&2
    exit 1
fi

if [ -z ${CERTBOT_VALIDATION} ]; then
    echo "Error: variable \$CERTBOT_VALIDATION is unset" >&2
    exit 1
fi

# Sanity check: in order to generate a dns record necessary for certificate generation
# you need to provide the cloudflare api token with Zone.DNS permissions to all zones
# https://dash.cloudflare.com/profile/api-tokens
if [ -z "${2}" ]; then
    echo "Error: you need to provide the Cloudflare API token in order to generate cert"
    exit 1
fi

# Sanity check: check if root domain was provided
if [ -z "${3}" ]; then
    echo "Error: you need to provide the root domain name"
    exit 1
fi

ACME_CHALLENGE=$(echo "_acme-challenge.${CERTBOT_DOMAIN}" | sed -e "s/.${3}//")

echo "ACME_CHALLENGE: ${ACME_CHALLENGE}"

# Get zone ID from domain name
ZONE_ID=$(curl --silent --show-error --request GET \
	--url "https://api.cloudflare.com/client/v4/zones?name=${3}" \
	--header 'Content-Type: application/json' \
	--header "Authorization: Bearer ${2}" \
	| jq -r '.result[0].id')

case $1 in 
    "create_record")
	url="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records"
	RECORD_ID=$(curl --silent --show-error --request POST \
	  --url $url \
	  --header 'Content-Type: application/json' \
	  --header "Authorization: Bearer ${2}" \
	  --data '{
	  "content": "'${CERTBOT_VALIDATION}'",
	  "name": "'${ACME_CHALLENGE}'",
	  "type": "TXT"
  }'| jq -r '.result.id')

	if [ ! -d /tmp/CERTBOT_$CERTBOT_DOMAIN ];then
        mkdir -m 0700 /tmp/CERTBOT_$CERTBOT_DOMAIN
	fi
	echo $ZONE_ID > /tmp/CERTBOT_$CERTBOT_DOMAIN/ZONE_ID
	echo $RECORD_ID > /tmp/CERTBOT_$CERTBOT_DOMAIN/RECORD_ID

	sleep 25
	;;
    "remove_record")
	if [ -f /tmp/CERTBOT_$CERTBOT_DOMAIN/ZONE_ID ]; then
					ZONE_ID=$(cat /tmp/CERTBOT_$CERTBOT_DOMAIN/ZONE_ID)
					rm -f /tmp/CERTBOT_$CERTBOT_DOMAIN/ZONE_ID
	fi

	if [ -f /tmp/CERTBOT_$CERTBOT_DOMAIN/RECORD_ID ]; then
					RECORD_ID=$(cat /tmp/CERTBOT_$CERTBOT_DOMAIN/RECORD_ID)
					rm -f /tmp/CERTBOT_$CERTBOT_DOMAIN/RECORD_ID
	fi
	if [ -n "${ZONE_ID}" ]; then
    if [ -n "${RECORD_ID}" ]; then
			curl --silent --show-error --request DELETE \
					--url "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}"\
					--header 'Content-Type: application/json' \
					--header "Authorization: Bearer ${2}"
		fi
	fi
	;;
esac
