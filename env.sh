VERSION_STRING="ebld20200508zuya"
LOCATION="westus2"
LOGGED_IN_USER_OBJ_ID="82e11ed5-c720-4c8d-b396-a2fcd9e4291f"
AKS_UNDERLAY_SUBSCRIPTION_ID="8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8"
DEPLOY_ENV="e2e"
SECTOR_NAME="es"
GIT_ROOT_DIRECTORY=${GIT_ROOT_DIRECTORY:-"$(git rev-parse --show-toplevel)"}

# bootstrap
HCP_PREFIX_OVERRIDE="hcp${VERSION_STRING}"
ETCD_BACKUPS_NAME_OVERRIDE="etcd${VERSION_STRING}"
REGIONAL_KEYVAULT_NAME_OVERRIDE="kvr${VERSION_STRING}"
INSTANCE_DNS_PREFIX_OVERRIDE="${VERSION_STRING}"

# sector
SECTOR_RESOURCE_GROUP_OVERRIDE="sector${VERSION_STRING}"
SECTOR_KEYVAULT_NAME_OVERRIDE="kvs${VERSION_STRING}"
ISSUER_NAME="Self"
DATABASE_RG_NAME_OVERRIDE="sql${VERSION_STRING}"
PRIMARY_DATABASE_SERVER_NAME_OVERRIDE="sqlp${VERSION_STRING}"