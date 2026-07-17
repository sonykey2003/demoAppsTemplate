#!/usr/bin/env bash
# O11y Log Observer Connect + TRANSPARENT federated search (search relay).
#
# Topology (no data is copied to the relay):
#   PROVIDER = on-prem (SPLUNK_ONPREM_*) — stores the logs in ${SPLUNK_INDEX} (HEC writes here).
#   FSH      = remote  (SPLUNK_REMOTE_*) — TRANSPARENT-mode federated search head; stores nothing;
#                                          `index=${SPLUNK_INDEX}` on the remote relays to the provider.
# The service account the FSH authenticates as lives on the PROVIDER (on-prem).
set -euo pipefail
source ./splunk/.env

case "${SPLUNK_ONPREM_ACS_URL}" in *staging*) fed_dom="stg.splunkcloud.com" ;; *) fed_dom="splunkcloud.com" ;; esac
PROVIDER_HOST="${SPLUNK_ONPREM_HOST:-${SPLUNK_ONPREM_STACK}.${fed_dom}}"   # on-prem: holds the data
FSH_HOST="${SPLUNK_REMOTE_HOST:-${SPLUNK_REMOTE_STACK}.${fed_dom}}"        # remote: transparent search relay

# Step 1: Acquire an ACS API token for each instance (session env only, not persisted).
echo "== provider (on-prem) token =="
export SPLUNK_ONPREM_ACS_TOKEN="$(curl -sS -u "$SPLUNK_USERNAME" -X POST "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/tokens" \
  -H 'Content-Type: application/json' \
  -d "{\"user\":\"${SPLUNK_USERNAME}\",\"audience\":\"${SPLUNK_TOKEN_AUDIENCE}\",\"expiresOn\":\"${SPLUNK_TOKEN_EXPIRES_ON}\"}" | jq -r '.token')"

echo "== FSH (remote) token =="
export SPLUNK_REMOTE_ACS_TOKEN="$(curl -sS -u "$SPLUNK_USERNAME" -X POST "${SPLUNK_REMOTE_ACS_URL%/}/${SPLUNK_REMOTE_STACK}/adminconfig/v2/tokens" \
  -H 'Content-Type: application/json' \
  -d "{\"user\":\"${SPLUNK_USERNAME}\",\"audience\":\"${SPLUNK_TOKEN_AUDIENCE}\",\"expiresOn\":\"${SPLUNK_TOKEN_EXPIRES_ON}\"}" | jq -r '.token')"

# Step 2: Create the data index on the PROVIDER (on-prem) only. The FSH (remote) must NOT have
# a local ${SPLUNK_INDEX}, or a plain index= search would hit the empty local index instead of
# transparently federating to the provider.
echo "== provider index (on-prem) =="
curl -sS -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -X POST "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/indexes" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"${SPLUNK_INDEX}\"}"


# Step 3: Create the federated service account on the PROVIDER (on-prem). The FSH authenticates
# as this account to search the provider. ACS ignores importRoles, so grant capabilities explicitly.
# TRANSPARENT mode REQUIRES the 'fsh_manage' capability on this role, or the provider authorizes
# the search (audit info=granted) but returns 0 results. Adding fsh_manage via ACS needs the
# 'Federated-Search-Manage-Ack: Y' header (compliance ack that fsh_manage can send results out).
echo "== provider role (on-prem) =="
curl -sS -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -H "Federated-Search-Manage-Ack: Y" -X POST "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/roles" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"${SPLUNK_LOC_ROLE}\",\"capabilities\":[\"search\",\"edit_tokens_own\",\"fsh_manage\"],\"srchIndexesAllowed\":[\"${SPLUNK_INDEX}\"],\"srchIndexesDefault\":[\"${SPLUNK_INDEX}\"],\"srchJobsQuota\":20}"

echo "== provider service account (on-prem) =="
curl -sS -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -X POST "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/users" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"${SPLUNK_LOC_SERVICE_ACCOUNT}\",\"password\":\"${SPLUNK_LOC_SERVICE_PASSWORD}\",\"roles\":[\"${SPLUNK_LOC_ROLE}\"],\"forceChangePass\":false}"


# Step 4: Create a HEC token on the On-Prem instance for log collection (ACS API).
# Creation is async: POST returns 202 with just the name, so fetch the token VALUE
# with a follow-up GET (repeat until it returns 200 instead of 404-hec-not-found).
echo "== provider HEC token create (on-prem) =="
curl -sS -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -X POST "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/inputs/http-event-collectors" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"${SPLUNK_HEC_TOKEN_NAME}\",\"allowedIndexes\":[\"${SPLUNK_INDEX}\"],\"defaultIndex\":\"${SPLUNK_INDEX}\",\"disabled\":false}"

# Retrieve the HEC token value for the collector
echo "== provider HEC token value (on-prem) =="
curl -sS -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/inputs/http-event-collectors/${SPLUNK_HEC_TOKEN_NAME}"


# Step 5: On the FSH (remote), open outbound :8089 so it can reach the PROVIDER (on-prem)
# for federated search. Destination subnets = the provider's public IP(s). Append-only + async.
[[ -n "${SPLUNK_FED_SUBNETS:-}" ]] || SPLUNK_FED_SUBNETS="$(dig +short "$PROVIDER_HOST" | awk '/^[0-9.]+$/{print $1"/32"}')"
prov_subnets_json="$(printf '%s\n' ${SPLUNK_FED_SUBNETS} | jq -R . | jq -sc 'map(select(. != ""))')"
[[ "${prov_subnets_json}" != "[]" ]] || { echo "No provider subnets resolved for ${PROVIDER_HOST}; set SPLUNK_FED_SUBNETS." >&2; exit 1; }
echo "== FSH outbound :8089 -> provider ${PROVIDER_HOST}: ${prov_subnets_json} =="
curl -sS -H "Authorization: Bearer ${SPLUNK_REMOTE_ACS_TOKEN}" -X POST "${SPLUNK_REMOTE_ACS_URL%/}/${SPLUNK_REMOTE_STACK}/adminconfig/v2/access/outbound-ports" \
  -H 'Content-Type: application/json' \
  -d "{\"outboundPorts\":[{\"port\":8089,\"subnets\":${prov_subnets_json}}],\"reason\":\"transparent federated search to the on-prem provider\"}"


# Step 5b: On the PROVIDER (on-prem), allow the FSH inbound to :8089 by adding the FSH's egress
# subnet(s) to the provider's 'search-api' IP allow list (closed by default). Append-only + async.
[[ -n "${SPLUNK_FSH_SUBNETS:-}" ]] || SPLUNK_FSH_SUBNETS="$(dig +short "$FSH_HOST" | awk '/^[0-9.]+$/{print $1"/32"}')"
fsh_subnets_json="$(printf '%s\n' ${SPLUNK_FSH_SUBNETS} | jq -R . | jq -sc 'map(select(. != ""))')"
[[ "${fsh_subnets_json}" != "[]" ]] || { echo "No FSH subnets resolved for ${FSH_HOST}; set SPLUNK_FSH_SUBNETS." >&2; exit 1; }
echo "== provider search-api allow list (+ FSH ${FSH_HOST}: ${fsh_subnets_json}) =="
curl -sS -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -X POST "${SPLUNK_ONPREM_ACS_URL%/}/${SPLUNK_ONPREM_STACK}/adminconfig/v2/access/search-api/ipallowlists" \
  -H 'Content-Type: application/json' \
  -d "{\"subnets\":${fsh_subnets_json}}"


# Step 6: On the FSH (remote), define a TRANSPARENT-mode federated provider pointing at the
# PROVIDER (on-prem). In transparent mode the provider's indexes are searchable by their REAL
# names, so `index=${SPLUNK_INDEX}` on the remote relays to on-prem — no "federated:" prefix and
# no federated-index mapping. splunkd REST on :8089; JWT as bearer.
echo "== FSH transparent provider -> ${PROVIDER_HOST}:8089 =="
curl -sS -k -H "Authorization: Bearer ${SPLUNK_REMOTE_ACS_TOKEN}" "https://${FSH_HOST}:8089/services/data/federated/provider" \
  -d name="${SPLUNK_FED_PROVIDER:-onprem_provider}" \
  -d type=splunk \
  --data-urlencode "hostPort=${PROVIDER_HOST}:8089" \
  --data-urlencode "serviceAccount=${SPLUNK_LOC_SERVICE_ACCOUNT}" \
  --data-urlencode "password=${SPLUNK_LOC_SERVICE_PASSWORD}" \
  -d mode=transparent \
  -d useFSHKnowledgeObjects=true \
  -d agreeWarningConsent=true \
  -d output_mode=json

# Step 7: On the FSH (remote), enable transparent role-based targeting and accept the
# deployment federated-search consent. Without these, `index=${SPLUNK_INDEX}` won't federate.
echo "== FSH federated settings (consent + role-based targeting) =="
curl -sS -k -H "Authorization: Bearer ${SPLUNK_REMOTE_ACS_TOKEN}" -X POST "https://${FSH_HOST}:8089/services/data/federated/settings/general" \
  -d needs_consent=0 \
  -d allowedAndDefaultFederatedProvidersEnabled=1 \
  -d output_mode=json

# Step 8: On the FSH (remote), make the provider a DEFAULT federated provider for the admin
# role, so a bare `index=${SPLUNK_INDEX}` transparently includes the on-prem provider.
echo "== FSH admin role -> default federated provider ${SPLUNK_FED_PROVIDER:-onprem_provider} =="
curl -sS -k -H "Authorization: Bearer ${SPLUNK_REMOTE_ACS_TOKEN}" -X POST "https://${FSH_HOST}:8089/services/authorization/roles/admin" \
  --data-urlencode "srchFederatedProvidersAllowed=${SPLUNK_FED_PROVIDER:-onprem_provider}" \
  --data-urlencode "srchFederatedProvidersDefault=${SPLUNK_FED_PROVIDER:-onprem_provider}" \
  -d output_mode=json

# Verify on the FSH (remote) in Splunk Web — transparent mode uses the REAL index name:
#   index=${SPLUNK_INDEX} earliest=-24h | stats count by splunk_federated_provider, splunk_server

# Cleanup: remove the OLD standard-mode federation objects created on on-prem when it was the
# FSH (harmless if already gone). Federation definitions only — no indexed data is deleted.
echo "== cleanup old standard-mode federation objects on on-prem =="
curl -sS -k -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -X DELETE "https://${PROVIDER_HOST}:8089/services/data/federated/index/${SPLUNK_INDEX}_fed" -o /dev/null -w '  index delete: %{http_code}\n' || true
curl -sS -k -H "Authorization: Bearer ${SPLUNK_ONPREM_ACS_TOKEN}" -X DELETE "https://${PROVIDER_HOST}:8089/services/data/federated/provider/remote_provider" -o /dev/null -w '  provider delete: %{http_code}\n' || true
# The remote may still hold a local '${SPLUNK_INDEX}' from the earlier build. In transparent mode a
# local index SHADOWS the federated one, so delete it on the remote if present (DESTRUCTIVE — only
# the fed-test seed events). Uncomment to run:
#   curl -sS -H "Authorization: Bearer ${SPLUNK_REMOTE_ACS_TOKEN}" -X DELETE "${SPLUNK_REMOTE_ACS_URL%/}/${SPLUNK_REMOTE_STACK}/adminconfig/v2/indexes/${SPLUNK_INDEX}"
