#!/bin/bash

workdir=$(dirname "$0")
source $workdir/create-resources.sh
source $workdir/env.sh

# echo "RP_REPO_ABSOLUTE_PATH=${RP_REPO_ABSOLUTE_PATH}"

# source ${RP_REPO_ABSOLUTE_PATH}/test/resources/scripts/create-resources.sh
# source ${RP_REPO_ABSOLUTE_PATH}/test/tf2/scripts/make-aks-tfvars.sh bootstrap

acr_subscription_id="${GLOBAL_RESOURCE_SUB_ID}"
acr_name="aksdeployment${DEPLOY_ENV}"
acr_resource_group="rp-common-${DEPLOY_ENV}"

artifacts_path=${RP_REPO_ABSOLUTE_PATH}/test/tf2/_entrypoints/staging/region_resources/.artifacts
configs_path=${artifacts_path}/config
filename=${configs_path}/envrc-${DEPLOY_ENV}-registry

filename="envrc-e2e-registry-1"
acr_name="hcpebld20200505zuyacr"
acr_resource_group="hcpebld20200505zuya-westus2"
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

## 04-charts_configs
chartsconfigs_dir=${GIT_ROOT_DIRECTORY}/chartsconfig
hcp_region_yaml = "${chartsconfigs_dir}/hcp/${DEPLOY_ENV}/${LOCATION}.yaml"

hcp_api_service_replicas=1
if [ "${DEPLOY_ENV}" == "e2e" ]; then
  hcp_api_service_replicas=3
fi

aad_audience="https://MSAzureCloud.onmicrosoft.com/AKS_INT_HCPApiServer"
if [ "${DEPLOY_ENV}" == "staging" ]; then
  aad_audience="https://MSAzureCloud.onmicrosoft.com/AKS_Prod_HCPApiServer"
fi

hcp_chart_repository_url="aksdeployment${DEPLOY_ENV}.azurecr.io/helm/v1/repo"

cat > "${hcp_region_yaml}" <<EOF
deploy_env: ${DEPLOY_ENV}
region: "${LOCATION}"

apiserver:
  replicas: ${hcp_api_service_replicas}
  cloudName: AzurePublicCloud
  keyvaultResourceId: https://vault.azure.net
  encryptionCertificateSecretPath: ${data.terraform_remote_state.sector.outputs.encryption_cert_secret_id}
  mcSqlserver:
    dbuser: "${local.sql_server_acs_user}"
    dbName: "${local.sql_db_name}"
    sqlServers: "${local.primary_database_server_name}"
    password: "${local.sql_primary_acs_dbuser_secret}"
  sqlserver:
    dbName: "${local.regional_db_name}"
    adminUser: "${local.sql_server_acs_user}"
    sqlServers: "${local.primary_database_server_name}"
    password: "${local.sql_primary_acs_dbuser_secret}"
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