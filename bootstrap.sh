#!/bin/bash

workdir=$(dirname "$0")
source $workdir/create-resources.sh
source $workdir/env.sh

# 1. create resource group
if [ "${HCP_PREFIX_OVERRIDE}" == "" ]; then
  resource_group_name="hcp-udl-${DEPLOY_ENV}"
else
  resource_group_name="${HCP_PREFIX_OVERRIDE}-${LOCATION}"
fi

aks::e2e::resource::resource_group "${resource_group_name}" "${LOCATION}" ""

# 2. create storage account
# region storage account
replacestr="${resource_group_name//-/}" # replace '-'' with ''
regional_storage_account_untruncated=$(echo $replacestr | tr '[:upper:]' '[:lower:]') # lowercase
stringlen=${#regional_storage_account_untruncated}
if [ "${stringlen}" -lt 24 ]; then
  regional_storage_account_name=${regional_storage_account_untruncated:0:$stringlen}
else
  regional_storage_account_name=${regional_storage_account_untruncated:0:24}
fi

aks::e2e::resource::storage_account "${regional_storage_account_name}" "${resource_group_name}" "${LOCATION}" "Hot"
aks::e2e::resource::storage_container "config" "${regional_storage_account_name}"

# etcd storage account
if [ "${ETCD_BACKUPS_NAME_OVERRIDE}" == "" ]; then
  tmpstring="etcd${LOCATION}${DEPLOY_ENV}"
  replacestr="${tmpstring//-/}" # replace '-'' with ''
  etcd_storage_account_name_untruncated=$(echo $replacestr | tr '[:upper:]' '[:lower:]') # lowercase
else
  etcd_storage_account_name_untruncated=$ETCD_BACKUPS_NAME_OVERRIDE
fi

stringlen=${#etcd_storage_account_name_untruncated}
if [ "${stringlen}" -lt 24 ]; then
  etcd_storage_account_name=${etcd_storage_account_name_untruncated:0:$stringlen}
else
  etcd_storage_account_name=${etcd_storage_account_name_untruncated:0:24}
fi

aks::e2e::resource::storage_account "${etcd_storage_account_name}" "${resource_group_name}" "${LOCATION}" "Cool"

# 3. rbac - subscription
# deploy_sp_object_id=DEPLOY_SP_OBJECT_ID
# customer_sp_object_id=CUSTOMER_SP_OBJECT_ID
# svc_sp_object_id=HCP_SERVICE_SP_OBJECT_ID
# subscription_id=AKS_UNDERLAY_SUBSCRIPTION_ID
if [ ${DO_ROLE_ASSIGNMENTS} == true ]; then
  echo "rbac - subscription - start"

  echo "AKS_UNDERLAY_SUBSCRIPTION_ID=${AKS_UNDERLAY_SUBSCRIPTION_ID}"
  echo "DEPLOY_SP_OBJECT_ID=${DEPLOY_SP_OBJECT_ID}"
  echo "CUSTOMER_SP_OBJECT_ID=${CUSTOMER_SP_OBJECT_ID}"
  echo "HCP_SERVICE_SP_OBJECT_ID=${HCP_SERVICE_SP_OBJECT_ID}"
  echo "GLOBAL_RESOURCE_SUB_ID=${GLOBAL_RESOURCE_SUB_ID}"

  scope="/subscriptions/${AKS_UNDERLAY_SUBSCRIPTION_ID}"
  aks::e2e::resource::role_assignment "${DEPLOY_SP_OBJECT_ID}" "${scope}" "Contributor"
  aks::e2e::resource::role_assignment "${CUSTOMER_SP_OBJECT_ID}" "${scope}" "Contributor"
  aks::e2e::resource::role_assignment "${HCP_SERVICE_SP_OBJECT_ID}" "${scope}" "Contributor"

  # 3. rbac - acr
  # 3. rbac - dns
  # root_dns_subscription_id=GLOBAL_RESOURCE_SUB_ID
  # customer_root_dns_resource_group = "hcp-global-dns-${var.deploy_env}"
  # customer_root_dns_zone="${var.deploy_env}.azmk8s.io"
  customer_root_dns_resource_group="hcp-global-dns-${DEPLOY_ENV}"
  customer_root_dns_zone="${DEPLOY_ENV}.azmk8s.io"
  scope="/subscriptions/${GLOBAL_RESOURCE_SUB_ID}/resourceGroups/${customer_root_dns_resource_group}/providers/Microsoft.Network/dnszones/${customer_root_dns_zone}"
  aks::e2e::resource::role_assignment "${DEPLOY_SP_OBJECT_ID}" "${scope}" "Contributor"

  # hcp_api_root_dns_resource_group = "hcp-global-dns-${var.deploy_env}"
  # hcp_api_root_dns_zone="${var.deploy_env}.aks.compute.azure.com"
  hcp_api_root_dns_resource_group="hcp-global-dns-${DEPLOY_ENV}"
  hcp_api_root_dns_zone="${DEPLOY_ENV}.aks.compute.azure.com"
  scope="/subscriptions/${GLOBAL_RESOURCE_SUB_ID}/resourceGroups/${hcp_api_root_dns_resource_group}/providers/Microsoft.Network/dnszones/${hcp_api_root_dns_zone}"
  aks::e2e::resource::role_assignment "${DEPLOY_SP_OBJECT_ID}" "${scope}" "Contributor"

  # 3. rbac - tfstate_tw-container_ro-rbac
  # tfstate_container_readonly="$${location}-sp-readonly"
  # tfstate_container_cluster="$${location}-sp-cluster"
  # tfstate_container_writable="$${location}-sp-writable"
  # tfstate_container_sector="$${location}-sp-sector"
  # tfstate_container_overlay="$${location}-sp-overlay"
  # resource_group_name=tfstate_resource_group
  # name=tfstate_storage_account_name
  resource_group="hcp-underlay-global-${DEPLOY_ENV}"
  storage_account_name="akstfstg${DEPLOY_ENV}"
  storage_account_id=$(az storage account show -g "${resource_group}" -n "${storage_account_name}" --query 'id' -o tsv)

  tfstate_container_readonly="${LOCATION}-sp-readonly"
  scope="${storage_account_id}/blobServices/default/containers/${tfstate_container_readonly}"
  aks::e2e::resource::role_assignment "${DEPLOY_SP_OBJECT_ID}" "${scope}" "Reader"

  tfstate_container_writable="${LOCATION}-sp-writable"
  scope="${storage_account_id}/blobServices/default/containers/${tfstate_container_writable}"
  aks::e2e::resource::role_assignment "${DEPLOY_SP_OBJECT_ID}" "${scope}" "Contributor"

  tfstate_container_sector="${LOCATION}-sp-sector"
  scope="${storage_account_id}/blobServices/default/containers/${tfstate_container_sector}"
  aks::e2e::resource::role_assignment "${DEPLOY_SP_OBJECT_ID}" "${scope}" "Contributor"

  echo "rbac - subscription - end"
fi

# 4. key vault
# user_object_id=LOGGED_IN_USER_OBJ_ID
if [ "${REGIONAL_KEYVAULT_NAME_OVERRIDE}" == "" ]; then
  regional_keyvault_name="hcp-${LOCATION}-${DEPLOY_ENV}"
else
  regional_keyvault_name=$REGIONAL_KEYVAULT_NAME_OVERRIDE
fi
stringlen=${#regional_keyvault_name}
if [ "${stringlen}" -lt 24 ]; then
  name_truncated=${regional_keyvault_name:0:$stringlen}
else
  name_truncated=${regional_keyvault_name:0:24}
fi
name_cleaned="${name_truncated//-/}"
az keyvault create --name "${name_cleaned}" --resource-group "${resource_group_name}" --location "${LOCATION}" --sku standard --enabled-for-template-deployment true --enabled-for-deployment true
az keyvault set-policy --name "${name_cleaned}" --object-id "${LOGGED_IN_USER_OBJ_ID}" --key-permissions create get update list --certificate-permissions create get update list --secret-permissions get list set

if [ ${ALL_IN_ONE_SP} == true ]; then
  echo "set keyvault policy - start"

  az keyvault set-policy --name "${name_cleaned}" --object-id "${DEPLOY_SP_OBJECT_ID}" --secret-permissions get list set
  az keyvault set-policy --name "${name_cleaned}" --object-id "${HCP_SERVICE_SP_OBJECT_ID}" --secret-permissions get list
  az keyvault set-policy --name "${name_cleaned}" --object-id "${CUSTOMER_SP_OBJECT_ID}" --secret-permissions get list

  echo "set keyvault policy - end"
fi

# 5. ssl admin certs
# hcp_api_tls_cert
if [ "${INSTANCE_DNS_PREFIX_OVERRIDE}" == "" ]; then
  instance_dns_prefix="${LOCATION}"
else
  instance_dns_prefix=$INSTANCE_DNS_PREFIX_OVERRIDE
fi
cert_name="hcp-api-${LOCATION}-certificate"
subject="hcp-api.${instance_dns_prefix}.${DEPLOY_ENV}.aks.compute.azure.com"
issuer_name="Self"

cat > hcp_api_tls_cert.json <<EOF
{
  "issuerParameters": {
    "certificateTransparency": null,
    "name": "${issuer_name}"
  },
  "keyProperties": {
    "curve": null,
    "exportable": true,
    "keySize": 4096,
    "keyType": "RSA",
    "reuseKey": true
  },
  "lifetimeActions": [
    {
      "action": {
        "actionType": "AutoRenew"
      },
      "trigger": {
        "daysBeforeExpiry": 30
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pem-file"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "cRLSign",
      "dataEncipherment",
      "digitalSignature",
      "keyEncipherment",
      "keyAgreement",
      "keyCertSign"
    ],
    "subject": "CN=${subject}",
    "validityInMonths": 12
  }
}
EOF

az keyvault certificate create --vault-name "${name_cleaned}" --name "${cert_name}" -p @hcp_api_tls_cert.json

# tunnelgateway_cert
cert_name="hcp-tun-${LOCATION}-certificate"
subject="*.tun.${instance_dns_prefix}.${DEPLOY_ENV}.azmk8s.io"
issuer_name="Self"

cat > tunnelgateway_cert.json <<EOF
{
  "issuerParameters": {
    "certificateTransparency": null,
    "name": "${issuer_name}"
  },
  "keyProperties": {
    "curve": null,
    "exportable": true,
    "keySize": 4096,
    "keyType": "RSA",
    "reuseKey": true
  },
  "lifetimeActions": [
    {
      "action": {
        "actionType": "AutoRenew"
      },
      "trigger": {
        "daysBeforeExpiry": 30
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pem-file"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "cRLSign",
      "dataEncipherment",
      "digitalSignature",
      "keyEncipherment",
      "keyAgreement",
      "keyCertSign"
    ],
    "subject": "CN=${subject}",
    "validityInMonths": 12
  }
}
EOF

az keyvault certificate create --vault-name "${name_cleaned}" --name "${cert_name}" -p @tunnelgateway_cert.json

if [ "${issuer_name}" == "" ]; then
  ## null_resource: issuer
  declare -r 'CHECKMARK=\xe2\x9c\x94'
  declare -r 'EXMARK=\xe2\x9c\x98'
  printf "Determining Issuer: "

  subscription_id=$AKS_UNDERLAY_SUBSCRIPTION_ID
  provider_name="SslAdmin"
  cloud="public"
  ISSUER_NAME_1=$(az keyvault certificate issuer list --subscription ${subscription_id} --vault-name ${name_cleaned} -o json | \
    jq -r '.[] | select(.provider == "${provider_name}" ) | .id | capture("/issuers/(?<issuer>.+)$") | .issuer')
  printf "%s" "$ISSUER_NAME_1 "

  if [[ -z "${ISSUER_NAME_1:-}" ]]; then
    printf "$EXMARK\n"
    if [ "${cloud}" == "china" ]; then
      echo "Please register mooncake keyvault manually, see aka.ms/sovereignonboard"
      exit 1
    fi
    az keyvault certificate issuer create \
      --subscription ${subscription_id} \
      --vault-name ${name_cleaned} \
      --issuer-name ${issuer_name} \
      --provider-name ${provider_name}
  else
    printf "$CHECKMARK\n"
  fi

  ## null_resource: akshost_keyvault_tls_contact_email
  contacts=$(az keyvault certificate contact list --subscription ${subscription_id} --vault-name ${name_cleaned})
  if echo "$contacts" | jq -r '.contactList[] | select(.emailAddress == "akshot@microsoft.com" ) | any'; then
    exit 0
  fi
  az keyvault certificate contact add \
    --subscription ${subscription_id} \
    --vault-name ${name_cleaned} \
    --email 'akshot@microsoft.com'
  if [ "${cloud}" == "china" ]; then
    if echo "$contacts" | jq -r '.contactList[] | select(.emailAddress == "aksonmooncake@microsoft.com" ) | any'; then
      exit 0
    fi
    az keyvault certificate contact add \
      --subscription ${subscription_id} \
      --vault-name ${name_cleaned} \
      --email 'aksonmooncake@microsoft.com'
  fi
fi
