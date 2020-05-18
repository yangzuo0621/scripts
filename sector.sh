#!/bin/bash

workdir=$(dirname "$0")
source $workdir/create-resources.sh

VERSION_STRING="ebld20200518zuya"
LOCATION="WESTUS2"

# 1. create keyvault and certs
SECTOR_RESOURCE_GROUP_OVERRIDE="sector${VERSION_STRING}"
if [ "${SECTOR_RESOURCE_GROUP_OVERRIDE}" == "" ]; then
  sector_resource_group="rp-common-${SECTOR_NAME}-${DEPLOY_ENV}${VERSION_STRING}"
else
  sector_resource_group=$SECTOR_RESOURCE_GROUP_OVERRIDE
fi

sector_group_location=$LOCATION

## resource group for sector
aks::e2e::resource::resource_group "${sector_resource_group}" "${sector_group_location}" ""

## keyvault for sector
SECTOR_KEYVAULT_NAME_OVERRIDE="kvs${VERSION_STRING}"
if [ "${SECTOR_KEYVAULT_NAME_OVERRIDE}" == "" ]; then
  sector_key_vault_name="acs-${SECTOR_NAME}-${DEPLOY_ENV}"
else
  sector_key_vault_name=$SECTOR_KEYVAULT_NAME_OVERRIDE
fi

az keyvault create --name "${sector_key_vault_name}" --resource-group "${sector_resource_group}" --location "${sector_group_location}" --sku premium --enabled-for-template-deployment true

## set access policy on keyvault
current_logged_in_user_object_id=$LOGGED_IN_USER_OBJ_ID
jit_group_object_id="5caed073-2b85-4f0b-8792-afde9e986a5e"
deploy_sp_object_id=$DEPLOY_SP_OBJECT_ID
hcp_service_sp_object_id=$HCP_SERVICE_SP_OBJECT_ID

az keyvault set-policy --name "${sector_key_vault_name}" --object-id "${current_logged_in_user_object_id}" \
    --key-permissions create get update list \
    --certificate-permissions create get update list \
    --secret-permissions get list set

az keyvault set-policy --name "${sector_key_vault_name}" --object-id "${jit_group_object_id}" \
    --key-permissions create get update list \
    --certificate-permissions create get update list \
    --secret-permissions get list set

az keyvault set-policy --name "${sector_key_vault_name}" --object-id "${deploy_sp_object_id}" \
    --key-permissions create get update list \
    --certificate-permissions create get update list \
    --secret-permissions get list set


az keyvault set-policy --name "${sector_key_vault_name}" --object-id "${hcp_service_sp_object_id}" \
    --secret-permissions get list

## generate certificates
## s2s_cert
ISSUER_NAME="Self"
if [ "${ISSUER_NAME}" == "" ]; then
  issuer_name="SslAdmin"
else
  issuer_name=$ISSUER_NAME
fi

cert_name="s2s-cert"
subject="s2s.${SECTOR_NAME}.${DEPLOY_ENV}.acs.azure.com"

cat > s2s_cert.json <<EOF
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
        "daysBeforeExpiry": 90
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pem-file"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subject": "CN=${subject}",
    "subjectAlternativeNames": {
      "dnsNames": [
        "${s2s.${SECTOR_NAME}.${DEPLOY_ENV}.acs.azure.com}"
      ]
    },
    "validityInMonths": 24
  }
}
EOF

az keyvault certificate create --vault-name "${sector_key_vault_name}" --name "${cert_name}" -p @s2s_cert.json

## s2s_cert
cert_name="ssl-cert"
subject="acs-${DEPLOY_ENV}${VERSION_STRING}.trafficmanager.net"

cat > ssl_cert.json <<EOF
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
        "daysBeforeExpiry": 90
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pem-file"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subject": "CN=${subject}",
    "subjectAlternativeNames": {
      "dnsNames": [
        "acs-int${VERSION_STRING}.trafficmanager.net",
        "acs-${DEPLOY_ENV}${VERSION_STRING}.trafficmanager.net"
      ]
    },
    "validityInMonths": 24
  }
}
EOF

az keyvault certificate create --vault-name "${sector_key_vault_name}" --name "${cert_name}" -p @ssl_cert.json

## mds_cert
cert_name="mds-cert"
subject="mds.${SECTOR_NAME}.${DEPLOY_ENV}.acs.azure.com"

cat > mds_cert.json <<EOF
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
        "daysBeforeExpiry": 90
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pkcs12"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subject": "CN=${subject}",
    "validityInMonths": 24
  }
}
EOF

az keyvault certificate create --vault-name "${sector_key_vault_name}" --name "${cert_name}" -p @mds_cert.json

## mdm_cert
cert_name="mdm-cert"
subject="mdm.${SECTOR_NAME}.${DEPLOY_ENV}.acs.azure.com"

cat > mdm_cert.json <<EOF
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
        "daysBeforeExpiry": 90
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pem-file"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subject": "CN=${subject}",
    "validityInMonths": 24
  }
}
EOF

az keyvault certificate create --vault-name "${sector_key_vault_name}" --name "${cert_name}" -p @mdm_cert.json

## encryption_cert
cert_name="encryption-cert"

cat > encryption_cert.json <<EOF
{
  "issuerParameters": {
    "certificateTransparency": null,
    "name": "Self"
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
        "daysBeforeExpiry": 90
      }
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pem-file"
  },
  "x509CertificateProperties": {
    "keyUsage": [
      "digitalSignature",
      "keyEncipherment"
    ],
    "subject": "CN=encryption",
    "validityInMonths": 24
  }
}
EOF

az keyvault certificate create --vault-name "${sector_key_vault_name}" --name "${cert_name}" -p @encryption_cert.json
