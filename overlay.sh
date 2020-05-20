#!/bin/bash

echo "RP_REPO_ABSOLUTE_PATH=${RP_REPO_ABSOLUTE_PATH}"

workdir=$(dirname "$0")
source $workdir/create-resources.sh
source $workdir/env.sh
source bootstrap.output
source sector.output
source region.output

output_file=overlay.output

## generate envrc-${DEPLOY_ENV}-registry
artifacts_path=${RP_REPO_ABSOLUTE_PATH}/test/tf2/_entrypoints/staging/overlay/.artifacts
configs_path="${artifacts_path}/config"
filename="${configs_path}/envrc-${DEPLOY_ENV}-registry"

acr_subscription_id="${GLOBAL_RESOURCE_SUB_ID}"
acr_name="aksdeployment${DEPLOY_ENV}"
acr_resource_group="rp-common-${DEPLOY_ENV}"

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

## extra_envrc
filename="${configs_path}/extra_env_rc"
cat > "${filename}" <<EOF
export AZURE_STORAGE_READ_URL="${rollout_toggles_blob_sas_uri}"
EOF

## envrcs
### svc-envrcs
envrcs_dir=${GIT_ROOT_DIRECTORY}/hcp/${DEPLOY_ENV}env
filename=${envrcs_dir}/envrc-${LOCATION}-svc-0

if [ "${HCP_PREFIX_OVERRIDE}" == "" ]; then
  hcp_prefix="hcp-udl-${DEPLOY_ENV}"
else
  hcp_prefix=${HCP_PREFIX_OVERRIDE}
fi

if [ "${INSTANCE_DNS_PREFIX_OVERRIDE}" == "" ]; then
  instance_dns_prefix=$LOCATION
else
  instance_dns_prefix=$INSTANCE_DNS_PREFIX_OVERRIDE
fi

hcp_api_prefix="hcp-api"
hcp_api_root_dns_zone=${DEPLOY_ENV}.aks.compute.azure.com
hcp_api_dns_zone="${instance_dns_prefix}.${hcp_api_root_dns_zone}"
customer_root_dns_zone="${DEPLOY_ENV}.azmk8s.io"
customer_dns_zone="${instance_dns_prefix}.${customer_root_dns_zone}"

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
