#!/bin/bash

workdir=$(dirname "$0")
source $workdir/create-resources.sh

VERSION_STRING="ebld20200518zuya"
LOCATION="WESTUS2"

# 1. create resource group
HCP_PREFIX_OVERRIDE="hcp${VERSION_STRING}"
if [ "${HCP_PREFIX_OVERRIDE}" == "" ]; then
    region_resource_group="hcp-udl-${DEPLOY_ENV}"
else
    region_resource_group="${HCP_PREFIX_OVERRIDE}-${LOCATION}"
fi

aks::e2e::resource::resource_group "${region_resource_group}" "${LOCATION}" ""

# 2. create storage account
# region storage account
replacestr="${region_resource_group//-/}" # replace '-'' with ''
regional_storage_account_untruncated=$(echo $replacestr | tr '[:upper:]' '[:lower:]') # lowercase
stringlen=${#regional_storage_account_untruncated}
if [ "${stringlen}" -lt 24 ]; then
    regional_storage_account_name=${regional_storage_account_untruncated:0:$stringlen}
else
    regional_storage_account_name=${regional_storage_account_untruncated:0:24}
fi

aks::e2e::resource::storage_account "${regional_storage_account_name}" "${region_resource_group}" "${LOCATION}" "Hot"
aks::e2e::resource::storage_container "config" "${regional_storage_account_name}"

# etcd storage account
ETCD_BACKUPS_NAME_OVERRIDE="etcd${VERSION_STRING}"
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

aks::e2e::resource::storage_account "${etcd_storage_account_name}" "${region_resource_group}" "${LOCATION}" "Cool"

# 3. rbac - subscription
# deploy_sp_object_id=DEPLOY_SP_OBJECT_ID
# customer_sp_object_id=CUSTOMER_SP_OBJECT_ID
# svc_sp_object_id=HCP_SERVICE_SP_OBJECT_ID
# subscription_id=AKS_UNDERLAY_SUBSCRIPTION_ID
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


# 4. key vault
REGIONAL_KEYVAULT_NAME_OVERRIDE="kvr${VERSION_STRING}"
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

az keyvault create --name "${name_cleaned}" --resource-group "${region_resource_group}" --location "${LOCATION}" --sku standard --enabled-for-template-deployment true --enabled-for-deployment true
az keyvault set-policy --name "${name_cleaned}" --object-id "${LOGGED_IN_USER_OBJ_ID}" --key-permissions create get update list --certificate-permissions create get update list --secret-permissions get list set

az keyvault set-policy --name "${name_cleaned}" --object-id "${DEPLOY_SP_OBJECT_ID}" --secret-permissions get list set
az keyvault set-policy --name "${name_cleaned}" --object-id "${HCP_SERVICE_SP_OBJECT_ID}" --secret-permissions get list
az keyvault set-policy --name "${name_cleaned}" --object-id "${CUSTOMER_SP_OBJECT_ID}" --secret-permissions get list

# 5. ssl admin certs

# hcp_api_tls_cert
INSTANCE_DNS_PREFIX_OVERRIDE="${VERSION_STRING}"
if [ "${INSTANCE_DNS_PREFIX_OVERRIDE}" == "" ]; then
    instance_dns_prefix="${LOCATION}"
else
    instance_dns_prefix=$INSTANCE_DNS_PREFIX_OVERRIDE
fi
cert_name="hcp-api-${LOCATIOn}-certificate"
subject="hcp-api.${instance_dns_prefix}.${DEPLOY_ENV}.aks.compute.azure.com"
issuer_name = "Self"

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
cert_name="hcp-tun-${LOCATIOn}-certificate"
subject="*.tun.${instance_dns_prefix}.${DEPLOY_ENV}.azmk8s.io"
issuer_name = "Self"

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
