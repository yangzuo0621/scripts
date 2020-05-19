#!/bin/bash

workdir=$(dirname "$0")
source $workdir/create-resources.sh
source $workdir/env.sh

output_file=sector.output

# 1. create keyvault and certs
if [ "${SECTOR_RESOURCE_GROUP_OVERRIDE}" == "" ]; then
  sector_resource_group="rp-common-${SECTOR_NAME}-${DEPLOY_ENV}${VERSION_STRING}"
else
  sector_resource_group=$SECTOR_RESOURCE_GROUP_OVERRIDE
fi

sector_group_location=$LOCATION

## resource group for sector
aks::e2e::resource::resource_group "${sector_resource_group}" "${sector_group_location}" ""

## keyvault for sector
if [ "${SECTOR_KEYVAULT_NAME_OVERRIDE}" == "" ]; then
  sector_key_vault_name="acs-${SECTOR_NAME}-${DEPLOY_ENV}"
else
  sector_key_vault_name=$SECTOR_KEYVAULT_NAME_OVERRIDE
fi

az keyvault create --name "${sector_key_vault_name}" --resource-group "${sector_resource_group}" --location "${sector_group_location}" --sku premium --enabled-for-template-deployment true
sector_key_vault_id=$(az keyvault show --name "${sector_key_vault_name}" --query id --output tsv)

cat > "${output_file}" <<EOF
sector_key_vault_name=${sector_key_vault_name}
sector_key_vault_id=${sector_key_vault_id}
EOF

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

if [ ${ALL_IN_ONE_SP} == true ]; then
  az keyvault set-policy --name "${sector_key_vault_name}" --object-id "${hcp_service_sp_object_id}" \
    --secret-permissions get list set
fi

if [ "${ISSUER_NAME}" == "" ]; then
  ## ssl_admin_issuer
  declare -r 'CHECKMARK=\xe2\x9c\x94'
  declare -r 'EXMARK=\xe2\x9c\x98'
  printf "Checking for SSLAdmin Issuers: "

  acrp_prod_subscription_id=$AKS_UNDERLAY_SUBSCRIPTION_ID
  provider_name="SslAdmin"
  ISSUER_NAMES=$(az keyvault certificate issuer list --subscription ${acrp_prod_subscription_id} --vault-name ${sector_key_vault_name} -o json | \
                    jq '.[] | select(.provider == "${provider_name}" ) | .id | capture("/issuers/(?<issuer>.+)$") | .issuer' | \
                    jq -sc '.' )
  printf "%s" "$ISSUER_NAMES = "

  if echo "$ISSUER_NAMES" | jq -e 'map(. == "${issuer_name}") | any' > /dev/null; then
  printf "$CHECKMARK\n"
  else
  printf "$EXMARK\n"
  az keyvault certificate issuer create \
    --subscription ${acrp_prod_subscription_id} \
    --vault-name ${sector_key_vault_name} \
    --issuer-name ${issuer_name} \
    --provider-name ${provider_name}
  fi

  ## keyvault_contact_email
  az keyvault certificate contact add --subscription ${acrp_prod_subscription_id} --vault-name ${sector_key_vault_name} --email "akshot@microsoft.com"
fi

# set issuer name
if [ "${ISSUER_NAME}" == "" ]; then
  issuer_name="SslAdmin"
else
  issuer_name=$ISSUER_NAME
fi

## generate certificates
## s2s_cert

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
        "s2s.${SECTOR_NAME}.${DEPLOY_ENV}.acs.azure.com"
      ]
    },
    "validityInMonths": 24
  }
}
EOF

az keyvault certificate create --vault-name "${sector_key_vault_name}" --name "${cert_name}" -p @s2s_cert.json
s2s_cert_secret_id=$(az keyvault certificate show --vault-name "${sector_key_vault_name}" --name "${cert_name}" --query id --output tsv)

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
ssl_cert_secret_id=$(az keyvault certificate show --vault-name "${sector_key_vault_name}" --name "${cert_name}" --query id --output tsv)

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
encryption_cert_secret_id=$(az keyvault certificate show --vault-name "${sector_key_vault_name}" --name "${cert_name}" --query id --output tsv)

cat >> "${output_file}" <<EOF
s2s_cert_secret_id=${s2s_cert_secret_id}
ssl_cert_secret_id=${ssl_cert_secret_id}
encryption_cert_secret_id=${encryption_cert_secret_id}
EOF

## resource group for database
if [ "${DATABASE_RG_NAME_OVERRIDE}" == "" ]; then
  database_rg_name="sql-${SECTOR_NAME}-${DEPLOY_ENV}"
else
  database_rg_name=$DATABASE_RG_NAME_OVERRIDE
fi
sector_group_location=$LOCATION

aks::e2e::resource::resource_group "${database_rg_name}" "${sector_group_location}" ""

## create sql server
if [ "${PRIMARY_DATABASE_SERVER_NAME_OVERRIDE}" == "" ]; then
  primary_database_server_name=acs-${LOCATION}-${DEPLOY_ENV}
else
  primary_database_server_name=$PRIMARY_DATABASE_SERVER_NAME_OVERRIDE
fi

sql_primary_location=$LOCATION

## generate password and store in keyvault
sql_admin_secret_name="sql-dbadmin-pwd"
sql_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')

sql_server_acs_user_secret_name="sql-dbuser-0415-2019-pwd"
sql_acs_user_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')

aks::e2e::resource::key_vault_secret "${sql_admin_secret_name}" "${sector_key_vault_name}" "${sql_password}"
aks::e2e::resource::key_vault_secret "${sql_server_acs_user_secret_name}" "${sector_key_vault_name}" "${sql_acs_user_password}"

sql_server_admin_user="dbadmin"
aks::e2e::resource::sql_server "${primary_database_server_name}" "${database_rg_name}" "${sql_primary_location}" "${sql_server_admin_user}" "${sql_password}"

## set sql firewall rule
firewall_rule_primary="acs-${LOCATION}-primary-firewall-rules"
aks::e2e::resource::sql_firewall_rule "${firewall_rule_primary}" "${database_rg_name}" "${primary_database_server_name}" "0.0.0.0" "0.0.0.0"

# May be removed when all tf2 are replaced
firewall_rule_primary_terraform="acs-${LOCATION}-terraform-firewall-rules"
aks::e2e::resource::sql_firewall_rule "${firewall_rule_primary_terraform}" "${database_rg_name}" "${primary_database_server_name}" "24.9.237.0" "24.9.237.255"

## create sql database
sql_db_name="acs"
aks::e2e::resource::sql_database "${sql_db_name}" "${database_rg_name}" "${primary_database_server_name}"

## create sql user
# if sqlcmd not found, link it.
if ! command -v sqlcmd; then
  ln -s /opt/mssql-tools/bin/sqlcmd /usr/local/bin/sqlcmd || true
fi

sql_server_acs_user="dbuser_0415_2019"
# INPUTS
DB_ADMIN_USER="${sql_server_admin_user}"
DB_ADMIN_PASSWORD="${sql_password}"
DB_NAME="${sql_db_name}"
SQL_SERVER="${primary_database_server_name}.database.windows.net"
DB_ACS_USER="${sql_server_acs_user}"
DB_ACS_PASSWORD="${sql_acs_user_password}"

create_user_query=$(cat <<EOF
CREATE USER ${DB_ACS_USER} WITH PASSWORD = '${DB_ACS_PASSWORD}'; 
GO
CREATE ROLE db_execproc; 
GO
EXEC sp_addrolemember N'db_execproc', N'${DB_ACS_USER}'; 
GO
GRANT EXECUTE ON SCHEMA::dbo TO db_execproc; 
GO
EOF
)

check_user=$(cat <<EOF
SELECT name FROM sysusers WHERE name="${DB_ACS_USER}"; 
GO
EOF
)

export SQLCMDPASSWORD="${DB_ADMIN_PASSWORD}"

sql_command="sqlcmd -S "${SQL_SERVER}" -U "${DB_ADMIN_USER}" -d "${DB_NAME}" -P "${DB_ADMIN_PASSWORD}""

if ${sql_command} -Q "${check_user}" | grep "0 rows affected" > /dev/null; then
  ${sql_command} -Q "${create_user_query}"
else
  echo "User ${DB_ACS_USER} already exists"
fi

primary_secret_id=$(az keyvault secret show --vault-name "${sector_key_vault_name}" --name "${sql_admin_secret_name}" --query id --output tsv)
primary_acs_dbuser_secret_id=$(az keyvault secret show --vault-name "${sector_key_vault_name}" --name "${sql_server_acs_user_secret_name}" --query id --output tsv)

sql_primary_secret=$primary_secret_id
if [ "${DEPLOY_ENV}" == "e2e" ]; then
  sql_server_acs_user=$sql_server_admin_user
  sql_primary_acs_dbuser_secret=$primary_secret_id
else
  sql_primary_acs_dbuser_secret=$primary_acs_dbuser_secret_id
fi

cat >> "${output_file}" <<EOF
primary_database_server_name=${primary_database_server_name}
primary_database_server_location=${sql_primary_location}
sql_server_admin_user=${sql_server_admin_user}
sql_admin_secret_name=${sql_admin_secret_name}
sql_server_acs_user=${sql_server_acs_user}
sql_server_acs_user_secret_name=${sql_server_acs_user_secret_name}
sql_server_resource_group=${database_rg_name}
sql_db_name=${sql_db_name}
sql_primary_acs_dbuser_secret=${sql_primary_acs_dbuser_secret}
sql_primary_secret=${sql_primary_secret}
EOF