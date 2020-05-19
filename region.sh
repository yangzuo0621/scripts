#!/bin/bash

echo "RP_REPO_ABSOLUTE_PATH=${RP_REPO_ABSOLUTE_PATH}"

workdir=$(dirname "$0")
source $workdir/create-resources.sh
source $workdir/env.sh
source bootstrap.output
source sector.output

output_file=region.output

## create regional sqldb
regional_db_name="regionaldb${LOCATION}"
aks::e2e::resource::sql_database "${regional_db_name}" "${sql_server_resource_group}" "${primary_database_server_name}"

primary_secret=$(az keyvault secret show --name "${sql_admin_secret_name}" --vault-name "${sector_key_vault_name}" --query value --output tsv)
primary_acs_dbuser_secret=$(az keyvault secret show --name "${sql_server_acs_user_secret_name}" --vault-name "${sector_key_vault_name}" --query value --output tsv)

# if sqlcmd not found, link it.
if ! command -v sqlcmd; then
  ln -s /opt/mssql-tools/bin/sqlcmd /usr/local/bin/sqlcmd || true
fi

## sql_create_user
# INPUTS
DB_ADMIN_USER="${sql_server_admin_user}"
DB_ADMIN_PASSWORD="${primary_secret}"
DB_NAME="${regional_db_name}"
SQL_SERVER="${primary_database_server_name}"
DB_ACS_USER="${sql_server_acs_user}"
DB_ACS_PASSWORD="${primary_acs_dbuser_secret}"

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

## generate envrc-${DEPLOY_ENV}-registry file
acr_subscription_id="${GLOBAL_RESOURCE_SUB_ID}"
acr_name="aksdeployment${DEPLOY_ENV}"
acr_resource_group="rp-common-${DEPLOY_ENV}"

artifacts_path=${RP_REPO_ABSOLUTE_PATH}/test/tf2/_entrypoints/staging/region_resources/.artifacts
configs_path=${artifacts_path}/config
filename=${configs_path}/envrc-${DEPLOY_ENV}-registry

az acr login --name "${acr_name}" --resource-group "${acr_resource_group}"

login_server=$(az acr show -n ${acr_name} --query loginServer)

admin_user_enabled=$(az acr show -n ${acr_name}  --query adminUserEnabled -o tsv)
if [ "${admin_user_enabled}" == true ]; then
  echo "acr admin user is enabled"
  admin_username=$(az acr credential show -n ${acr_name} --query username)
  admin_password=$(az acr credential show -n ${acr_name} --query passwords[0].value)
else
  echo "acr admin user is disabled"
  admin_username=""
  admin_password=""
fi

cat > "${filename}" <<EOF
export REGISTRY=${login_server}
export IMAGE_REGISTRY=${login_server}

export REGISTRY_USERNAME=${admin_username}
export REGISTRY_PASSWORD=${admin_password}
export ImageRegistryUserName=${admin_username}
export ImageRegistryPassword=${admin_password}

export TUNNEL_REGISTRY=${login_server}/
export TUNNEL_IMAGE_REGISTRY=${login_server}
export TUNNEL_REGISTRY_USERNAME=${admin_username}
export TUNNEL_REGISTRY_PASSWORD=${admin_password}
EOF

## 02-hcp_svc_infrastructure

### service_sp_generic_deploy_secrets
az keyvault secret set --name "aks-${LOCATION}-customer-app-sp-id" --value "${HCP_SERVICE_SP_APP_ID}" --vault-name "${regional_vault}"
az keyvault secret set --name "aks-${LOCATION}-customer-app-sp-pw" --value "${DEPLOY_SP_APP_PASSWORD}" --vault-name "${regional_vault}"
az keyvault secret set --name "aks-${LOCATION}-service-app-sp-id" --value "${HCP_SERVICE_SP_APP_ID}" --vault-name "${regional_vault}"
az keyvault secret set --name "aks-${LOCATION}-service-app-sp-pw" --value "${DEPLOY_SP_APP_PASSWORD}" --vault-name "${regional_vault}"
password_base64=$(echo "${DEPLOY_SP_APP_PASSWORD}" | base64)
az keyvault secret set --name "hcp-api-${LOCATION}-hcp-deployment-sp-pw" --value "${password_base64}" --vault-name "${regional_vault}"

### hcp_service_environment
### cosmsdb
cosmos_name_untruncated=${regional_resource_group}
stringlen=${#cosmos_name_untruncated}
if [ "${stringlen}" -lt 35 ]; then
  cosmos_name_truncated=${cosmos_name_untruncated:0:$stringlen}
else
  cosmos_name_truncated=${cosmos_name_untruncated:0:35}
fi
cosmos_name_cleaned="${cosmos_name_truncated//-/}" # replace '-'' with ''

if [ "${TF_VAR_skip_cosmosdb_creation}" == false ]; then
  echo "create cosmosdb"
  cosmos_location=${LOCATION}
  cosmos_resource_group=${regional_resource_group}
  az cosmosdb create --name "${cosmos_name_cleaned}" --resource-group "${cosmos_resource_group}" --kind MongoDB --default-consistency-level Strong --locations regionName=${cosmos_location} failoverPriority=0

  cosmos_connection_string=$(az cosmosdb keys list --name "${cosmos_name_cleaned}" --resource-group "${cosmos_resource_group}"  --type connection-strings | jq -r '.connectionStrings[0].connectionString')

  az keyvault secret set \
      --name "${cosmos_name_cleaned}-cosmosdb-connection-string" \
      --value "${cosmos_connection_string}" \
      --vault-name "${regional_vault}"
else
  cosmosdb_connection_string_passthrough=${TF_VAR_cosmosdb_connection_string_passthrough}
  az keyvault secret set \
      --name "${cosmos_name_cleaned}-cosmosdb-connection-string" \
      --value "${cosmosdb_connection_string_passthrough}" \
      --vault-name "${regional_vault}"
fi

## dns
if [ "${INSTANCE_DNS_PREFIX_OVERRIDE}" == "" ]; then
  instance_dns_prefix=$LOCATION
else
  instance_dns_prefix=$INSTANCE_DNS_PREFIX_OVERRIDE
fi
customer_root_dns_zone="${DEPLOY_ENV}.azmk8s.io"
customer_root_dns_resource_group="hcp-global-dns-${DEPLOY_ENV}"

dns_name="${instance_dns_prefix}.${customer_root_dns_zone}"
dns_rg="${regional_resource_group}"
aks::e2e::resource::dns_zone "${dns_name}" "${dns_rg}"

name_servers=$(az network dns zone show --resource-group "${dns_rg}" --name "{dns_name}" --query nameServers --output tsv)

customer_root_name=${customer_root_dns_zone}
customer_root_dns_resource_group="hcp-global-dns-${DEPLOY_ENV}"

for item in ${name_servers[*]};
do
  az network dns record-set ns add-record \
    --zone-name "${customer_root_name}" \
    --resource-group "${customer_root_dns_resource_group}" \
    --nsdname "${item}" \
    --record-set-name "${instance_dns_prefix}" \
    --ttl 300
done

## 04-charts_configs
chartsconfigs_dir=${GIT_ROOT_DIRECTORY}/chartsconfig
hcp_region_yaml="${chartsconfigs_dir}/hcp/${DEPLOY_ENV}/${LOCATION}.yaml"

registry_url="aksdeployment${DEPLOY_ENV}.azurecr.io"
rp_exposed_to_internet=true
if [ "${DEPLOY_ENV}" == "e2e" ]; then
  rp_exposed_to_internet=false
fi

hcp_api_service_replicas=1
container_service_async_replicas=1
container_service_replicas=1
if [ "${DEPLOY_ENV}" == "e2e" ]; then
  hcp_api_service_replicas=3
  container_service_async_replicas=3
  container_service_replicas=3
fi

aad_audience="https://MSAzureCloud.onmicrosoft.com/AKS_INT_HCPApiServer"
if [ "${DEPLOY_ENV}" == "staging" ]; then
  aad_audience="https://MSAzureCloud.onmicrosoft.com/AKS_Prod_HCPApiServer"
fi

### hcp_regional_yaml ###
hcp_chart_repository_url="aksdeployment${DEPLOY_ENV}.azurecr.io/helm/v1/repo"

cat > "${hcp_region_yaml}" <<EOF
deploy_env: ${DEPLOY_ENV}
region: "${LOCATION}"

apiserver:
  replicas: ${hcp_api_service_replicas}
  cloudName: AzurePublicCloud
  keyvaultResourceId: https://vault.azure.net
  encryptionCertificateSecretPath: ${encryption_cert_secret_id}
  mcSqlserver:
    dbuser: "${sql_server_acs_user}"
    dbName: "${sql_db_name}"
    sqlServers: "${primary_database_server_name}"
    password: "${sql_primary_acs_dbuser_secret}"
  sqlserver:
    dbName: "${regional_db_name}"
    adminUser: "${sql_server_acs_user}"
    sqlServers: "${primary_database_server_name}"
    password: "${sql_primary_acs_dbuser_secret}"
  resources:
    cpuRequest: 100m
    memoryRequest: 100M
  authYaml: |
    keyCacheRetriesCount: 3
    keyCacheRetryIntervalInMinutes: 15
    keyCacheRefreshIntervalInHours: 24
    signingKeyURL: "https://login.windows.net/${TENANT_ID}/discovery/keys"
    audience: "${aad_audience}"
    servicePrincipalIDs:
      - "28863530-0785-4edd-a9db-2213154244cb"
      - "4f0ce18d-1f2d-443e-bb5c-3d4416687887"
      - "7ada1bac-416b-419e-b1d7-1421ab03ecdc"
      - "dba2ed9a-6d12-4758-981f-de0e886182c4"
      - "009c3e4d-f9bf-420a-9890-430eca3eb684"
      - "8f5c607c-14b9-409d-95bd-1266c193a4a5"
      - "fe3666d9-187f-4884-882e-85b5d0c2b2f0"
      - "13bec9da-7208-4aa0-8fc7-47b25e26ff5d"
    allowedIssuers:
      - "https://sts.windows.net/72f988bf-86f1-41af-91ab-2d7cd011db47/"
      - "https://sts.windows.net/33e01921-4d64-4f8c-a055-5bdaffd5e33d/"
controlloop:
  chartRepo:
    url: "https://${hcp_chart_repository_url}"
  aadAudience: "${aad_audience}"

sqlmanager:
  skip_preinstall_hook: false
EOF

### hcp_region_yaml ###
acsrp_config_base_file="acs-common.json"
if [ "${DEPLOY_ENV}" == "staging" ]; then
  acsrp_config_base_file="acs-prod.json"
fi

acsrp_config_file_name="acs-${LOCATION}-${DEPLOY_ENV}.json"
acsrp_config_admin_file_name="acs-${LOCATION}-admin-${DEPLOY_ENV}.json"

s2s_cert_to_use=${s2s_cert_secret_id}
hcp_skip_ssl=false
if [ "${DEPLOY_ENV}" == "e2e" ];then
  hcp_skip_ssl=true
  s2s_cert_to_use="https://akse2ekeyvault.vault.azure.net/secrets/acsrp-s2s-cert/77f265a78f4740cc88987d3c45b96e0e"
fi

customer_dns_zone="${instance_dns_prefix}.${customer_root_dns_zone}"

## acsrp_config
acsrp_configuration_content=$(cat <<-EOF
{
  "baseFile": "${acsrp_config_base_file}",
  "sector": "${SECTOR_NAME}",
  "regions": [
    "${LOCATION}"
  ],
  "applicationID": "${APPLICATION_ID}",
  "featureAADServerApplicationID": "4f970234-6330-4470-bf3f-ef9a18e24d1b",
  "featureAADClientApplicationID": "582a379c-2fa4-4006-a714-6bef870cd9d8",
  "tenantID": "${APPLICATION_TENANT_ID}",
  "clientCertificateSecretPath": "${s2s_cert_to_use}",
  "sslSecretPath": "${ssl_cert_secret_id}",
  "encryptionCertificateSecretPath": "${encryption_cert_secret_id}",
  "rpDeployedRegions": [
    "${LOCATION}"
  ],
  "rpConfig": {
    "disableServicePrincipalRoleAssignment": false,
    "services": [
      "AKS"
    ]
  },
  "sqlStoreConfig": {
    "sqlservers": [
      "${primary_database_server_name}"
    ],
    "userid": "${sql_server_acs_user}",
    "password": "${sql_primary_acs_dbuser_secret}",
    "database": "${sql_db_name}"
  },
  "devopsSubscriptionID": "${GLOBAL_RESOURCE_SUB_ID}",
  "devopsResourceGroup": "hcp-underlay-global-${DEPLOY_ENV}",
  "devopsDomainName": "${DEPLOY_ENV}.aksapp.io",
  "hcpConfig": {
    "skipSSL": ${hcp_skip_ssl},
    "regionOverrides": {
      "${LOCATION}": {
        "endpointUri": "https://${hcp_api_uri}",
        "host": "${hcp_api_uri}",
        "managedClusterConfig": {
          "resourceLimitPerSubscription": 100,
          "exemptSubscriptions": [
          ]
        },
        "subscriptionId": "${regional_subscription_id}",
        "regionResourceGroupName": "${regional_resource_group}",
        "customerDNSZone": "${customer_dns_zone}",
        "etcdBackupStorageAccountName": "${etcd_backups_storage_account}"
      }
    },
    "asyncWait": 9000,
    "aadAudience": "${aad_audience}"
  }
}
EOF
)

acsrp_configs_dir=${GIT_ROOT_DIRECTORY}/acsconfigs
filename="${acsrp_configs_dir}/${acsrp_config_file_name}"
cat > "${filename}" <<EOF
${acsrp_configuration_content}
EOF

## acsrp_config_admin
acsrp_configuration_admin_content=$(cat <<-EOF
{
  "baseFile": "${acsrp_config_file_name}",
  "sqlStoreConfig": {
    "userid": "${sql_server_admin_user}",
    "password": "${sql_primary_secret}"
  }
}
EOF
)

filename="${acsrp_configs_dir}/${acsrp_config_admin_file_name}"
cat > "${filename}" <<EOF
${acsrp_configuration_admin_content}
EOF


acsrp_configuration_content_base64=$(echo "${acsrp_configuration_content}" | base64)

pav2_storage_account_name="akspav2int"
if [ "${DEPLOY_ENV}" == "staging" ]; then
  pav2_storage_account_name="akspav2staging"
fi

pav2_sas_key_url="https://aks-billing-int.vault.azure.net/secrets/stagingpav2storagesaskey"

rp_region_yaml="${chartsconfigs_dir}/${DEPLOY_ENV}/${LOCATION}.yaml"
cat > "${rp_region_yaml}" <<EOF
deploy_env: ${DEPLOY_ENV}
region: "${LOCATION}"
config: acs-${LOCATION}-${DEPLOY_ENV}.json
admin_config: acs-${LOCATION}-admin-${DEPLOY_ENV}.json

container_service:
  replicas: ${container_service_replicas}
  exposed_to_internet: ${rp_exposed_to_internet}
  ssl_secret_path: ${ssl_cert_secret_id}
  allowed_acis_thumbprint_regex: ^(BEE0780F6BEECDCDAFD011906E48331F36400DED|F6659F7653BB1552AC6C303521977D86EE3DEBFB)$
  ssl_intermediate_cert_path: /nginx/Microsoft_IT_TLS_CA_2.pem

container_service_async:
  replicas: ${container_service_async_replicas}

sqlmanager:
  skip_preinstall_hook: false

regionallooper:
  hcp_endpoint_uri: "https://${hcp_api_uri}"
  hcp_aad_audience: "${aad_audience}"
  hcpSkipSSL: ${local.hcp_skip_ssl}

jithandler:
  hcp_endpoint_uri: "https://${hcp_api_uri}"
  hcp_aad_audience: "${aad_audience}"
  hcpSkipSSL: ${hcp_skip_ssl}
  authYaml: |
    keyCacheRetriesCount: 3
    keyCacheRetryIntervalInMinutes: 15
    keyCacheRefreshIntervalInHours: 24

mc_reconcile_controller:
  hcp_endpoint_uri: "https://${hcp_api_uri}"
  hcp_aad_audience: "${aad_audience}"
  hcpSkipSSL: ${hcp_skip_ssl}

billing:
  hcp_endpoint_uri: "https://${hcp_api_uri}"
  hcp_aad_audience: "${aad_audience}"
  hcpSkipSSL: ${hcp_skip_ssl}
  storage_account_name: "${pav2_storage_account_name}"
  sas_key_secret_url: "${pav2_sas_key_url}"

dev_config:
  acs_dev_json: |
    ${acsrp_configuration_content_base64}
EOF

### registry_yaml ###
registry_yaml="${chartsconfigs_dir}/${DEPLOY_ENV}/registry.yaml"
cat > "${registry_yaml}" <<EOF
registry: ${registry_url}
username: aksdeployment${DEPLOY_ENV}

container_service:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

container_service_async:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

jithandler:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

jitcontroller:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

queuewatcher:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

regionallooper:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

mc_reconcile_controller:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

billing:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always

sqlmanager:
  image:
    registry: ${registry_url}
    org: acs
    pull_policy: Always
  clear_on_delete: false
  create_dbuser: false
  update_schema: false
EOF

### nginx_ingress_controller_yaml ###
nginx_ingress_controller_yaml="${chartsconfigs_dir}/${DEPLOY_ENV}/nginx-ingress/controller.yaml"
cat > "${registry_yaml}" <<EOF
controller:
  config:
    ssl-protocols: "TLSv1.2"
    ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384"
    ssl-ecdh-curve: "prime256v1:secp384r1"
    ssl_session_cache: "shared:SSL:10m"
    ssl-session-tickets: "false"
    enable-vts-status: "true"
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10254"
  extraArgs:
    annotations-prefix: "ingress.kubernetes.io"
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
EOF

### shared configs
toggle_file_name="${configs_path}/rollout_toggles.yaml"
az storage blob upload \
    --container-name "${regional_storage_account_config_storage}" \
    --account-name "${regional_storage_account}" \
    --name "toggles" \
    --file "${toggle_file_name}" \
    --type block

url=$(az storage blob url --account-name "${regional_storage_account}" --container-name "${regional_storage_account_config_storage}" --name toggles --output tsv)
regional_storage_account_sas_token=$(az storage account generate-sas --permissions rw --account-name "${regional_storage_account}" --resource-types sco --services b --start 2000-01-01 --expiry 4000-01-01 --https-only --output tsv)
rollout_toggles_blob_sas_uri="${url}?${regional_storage_account_sas_token}"

## envrcs
### svc-envrcs
envrcs_dir=${GIT_ROOT_DIRECTORY}/hcp/${DEPLOY_ENV}env
filename=${envrcs_dir}/envrc-${LOCATION}-svc-0

if [ "${HCP_PREFIX_OVERRIDE}" == "" ]; then
  hcp_prefix="hcp-udl-${DEPLOY_ENV}"
else
  hcp_prefix=${HCP_PREFIX_OVERRIDE}
fi

hcp_api_prefix="hcp-api"
hcp_api_root_dns_zone=${DEPLOY_ENV}.aks.compute.azure.com
hcp_api_dns_zone="${instance_dns_prefix}.${hcp_api_root_dns_zone}"

cat > "${filename}" <<EOF
# This should only be used in E2E/INTv2/Staging

cluster_id=svc-0
region=${LOCATION}
region_subscription=${AKS_UNDERLAY_SUBSCRIPTION_ID}

etcd_storage_account_name=${etcd_backups_storage_account}

export HCP_PREFIX=${hcp_prefix}
export HCP_VAULT_NAME=${hcp_service_vault}
export HCP_CUSTOMER_DNS_ZONE=${customer_dns_zone}
export CUSTOMER_ROOT_DNS_ZONE=${customer_root_dns_zone}

export HCP_API_DNS_ZONE=${hcp_api_prefix}.${hcp_api_dns_zone}

source hcp/${DEPLOY_ENV}env/defaults/envrc-default
source hcp/${DEPLOY_ENV}env/defaults/envrc-svc-default

## RBAC settings
export UNDERLAY_RBAC=true
EOF

## cx-envrcs
## TODO need to ensure the underlay_cluster_count
filename=${envrcs_dir}/envrc-${LOCATION}-cx-0
service_underlay_name="${hcp_prefix}-${LOCATION}-svc-0"
cat > "${filename}" <<EOF
# This should only be used in E2E/INTv2/Staging

cluster_id=cx-0
region=${LOCATION}
region_subscription=${AKS_UNDERLAY_SUBSCRIPTION_ID}

etcd_storage_account_name=${etcd_backups_storage_account}

export HCP_PREFIX=${hcp_prefix}
export HCP_VAULT_NAME=${customer_underlay_vault}
export HCP_CUSTOMER_DNS_ZONE=${customer_dns_zone}
export CUSTOMER_ROOT_DNS_ZONE=${customer_root_dns_zone}
export DEPLOY_CCP_PROXY_INGRESS=true

export HCP_API_DNS_ZONE=${hcp_api_prefix}.${hcp_api_dns_zone}
export CCP_PROXY_INGRESS_CLASS="ccpproxy-class-${VERSION_STRING}"
export HCP_CLUSTER_ID=${service_underlay_name}

source hcp/${DEPLOY_ENV}env/defaults/envrc-default
source hcp/${DEPLOY_ENV}env/defaults/envrc-cx-default

## RBAC settings
export UNDERLAY_RBAC=true
EOF


## svc-envrcs-default
filename="${envrcs_dir}/envrc-${LOCATION}-svc-default"
cat > "${filename}" <<EOF
region=${LOCATION}
region_subscription=${AKS_UNDERLAY_SUBSCRIPTION_ID}

export HCP_PREFIX=${hcp_prefix}
export HCP_VAULT_NAME=${customer_underlay_vault}

export etcd_storage_account_name=${etcd_backups_storage_account}

source hcp/e2eenv/defaults/envrc-default
source hcp/e2eenv/defaults/envrc-svc-default
EOF

## cx-envrcs-default
filename="${envrcs_dir}/envrc-${LOCATION}-cx-default"
cat > "${filename}" <<EOF
region=${LOCATION}
region_subscription=${AKS_UNDERLAY_SUBSCRIPTION_ID}

export HCP_PREFIX=${hcp_prefix}
export HCP_VAULT_NAME=${customer_underlay_vault}

export etcd_storage_account_name=${etcd_backups_storage_account}

source hcp/e2eenv/defaults/envrc-default
source hcp/e2eenv/defaults/envrc-cx-default
EOF

cat > "${output_file}" <<EOF
rollout_toggles_blob_sas_uri=${rollout_toggles_blob_sas_uri}
acsrp_configuration_content=${acsrp_configuration_content}
acsrp_config_file_name=${acsrp_config_file_name}
acsrp_configuration_admin_content=${acsrp_configuration_admin_content}
acsrp_config_admin_file_name=${acsrp_config_admin_file_name}
EOF