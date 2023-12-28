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

# Support to get the root domain from a subdomain
ROOT_DOMAIN="$(echo "${CERTBOT_DOMAIN}" | sed -r 's/www.//g' | sed -r 's/[a-zA-Z0-9]+.//')"
CERTBOT_DOMAIN="$(echo "${CERTBOT_DOMAIN}" | sed -r 's/www.//g')"
CERTBOT_VERIFICATION_DOMAIN_NAME="$(echo "_acme-challenge.${CERTBOT_DOMAIN}" | sed -r 's/\."${ROOT_DOMAIN}"//')"

# Get zone ID from domain name
ZONE_ID=$(curl --silent --show-error --request GET \
	--url "https://api.cloudflare.com/client/v4/zones?name=${ROOT_DOMAIN}" \
	--header 'Content-Type: application/json' \
	--header "Authorization: Bearer ${2}" \
	| jq -r '.result[0].id')

case $1 in 
    "create_record")
	url="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records"
	response=$(curl --silent --show-error --request POST \
	  --url $url \
	  --header 'Content-Type: application/json' \
	  --header "Authorization: Bearer ${2}" \
	  --data '{
	  "content": "'${CERTBOT_VALIDATION}'",
	  "name": "${CERTBOT_VERIFICATION_DOMAIN_NAME}",
	  "type": "TXT"
  }')
	echo -n "${response}"
	sleep 10
	;;
    "remove_record")
	url_get_record_id="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${CERTBOT_VERIFICATION_DOMAIN_NAME}"
	record_id=$(curl --silent --show-error --request GET \
	  --url $url_get_record_id \
	  --header 'Content-Type: application/json' \
	  --header "Authorization: Bearer ${2}" \
	  | jq -r '.result[0].id')
	
	url_delete_record="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}"
	response=$(curl --silent --show-error --request DELETE \
	  --url $url_delete_record \
	  --header 'Content-Type: application/json' \
	  --header "Authorization: Bearer ${2}")
	;;
esac
