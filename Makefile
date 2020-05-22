deploy_all: create_resource_group create_key_vault create_storage_account create_storage_container create_storage_blob
	@echo "deploy_all"

create_resource_group:
	@echo "create_resource_group..."
	## reginal resource group (_bootstrap/regional_resource_group.tf)
	## sector resource group (sector_resources/01-keyvault-and-certs.tf)
	## database resource group (sector_resources/02-sql.tf)

create_key_vault: create_resource_group
	@echo "create_key_vault..."
	## regional keyvault [regional resouce group] (_bootstrap/02-keyvault-and-acls.tf)
	## sector keyvault [sector resouce group] (sector_resources/01-keyvault-and-certs.tf)

add_access_policy_on_keyvault: create_key_vault
	@echo "add_access_policy_on_keyvault"
	## sector keyvault (sector_resources/01-keyvault-and-certs.tf)
	##   current_logged_in_user_object_id
	##   jit_group_object_id
	##   deploy_sp_object_id
	##   hcp_service_sp_object_id (if all_in_one_sp is enabled)
	## regional keyvault (_bootstrap/02-keyvault-and-acls.tf)
	##	 user_object_id
	##   deploy_sp_object_id (if all_in_one_sp is enabled)
	##   svc_sp_object_id (if all_in_one_sp is enabled)
	##   customer_sp_object_id (if all_in_one_sp is enabled)

create_key_vault_certificate: create_key_vault
	echo "create_key_vault_certificate"
	## s2s-cert [sector keyvault] (sector_resources/01-keyvault-and-certs.tf)
	## ssl-cert [sector keyvault] (sector_resources/01-keyvault-and-certs.tf)
	## mds-cert [sector keyvault] (sector_resources/01-keyvault-and-certs.tf)
	## mdm-cert [sector keyvault] (sector_resources/01-keyvault-and-certs.tf)
	## encryption-cert [sector keyvault] (sector_resources/01-keyvault-and-certs.tf)

	## hcp_api_tls_cert [reginal keyvault] (_bootstrap/03-ssl-admin_certs.tf)
	## tunnelgateway_cert [reginal keyvault] (_bootstrap/03-ssl-admin_certs.tf)

create_storage_account: create_resource_group
	@echo "create_storage_account"
	## regional storage account [regional resouce group] (_bootstrap/02-storage-accounts.tf)
	## etcd storage account [regional resouce group] (_bootstrap/02-storage-accounts.tf)

create_storage_container: create_storage_account
	@echo "create_storage_account"
	## config storage container [regional storage account] (_bootstrap/02-storage-accounts.tf)

create_storage_blob: create_storage_container
	@echo "create_storage_blob"
	## toggles storage blob [regional storage account, regional storage container] (region_resouces/07-shared_config.tf)

create_sql: create_sql_server create_sql_firewall_rule create_sql_database create_sql_user
	@echo "create_sql"

create_sql_server: create_resource_group create_sql_password
	@echo "create_sql_server"
	## primary database server [database resource group] (sector_resouces/02-sql.tf)

create_sql_firewall_rule: create_sql_server
	@echo "create_sql_firewall_rule"
	## primary firewall rules [primary database server] (sector_resouces/02-sql.tf)
	## terraform firewall rules [primary database server] (sector_resouces/02-sql.tf) -- should be removed when totally replacing tf2

create_sql_database: create_sql_server
	@echo "create_sql_database"
	## primary sql database [primary database server] (sector_resouces/02-sql.tf)
	## regional sql database [primary database server] (region_resources/09-regional_sqldbs.tf)

create_sql_password: create_key_vault
	@echo "create_sql_password"
	## sql admin secret [sector keyvault] (sector_resources/02-sql.tf)
	## sql acs user secret [sector keyvault] (sector_resources/02-sql.tf)

create_sql_user: create_key_vault create_sql_database
	@echo "create_sql_user"
	## primary sql database [primary database server] (sector_resources/02-sql.tf)
	## regional sql database [primary database server] (region_resources/09-regional_sqldbs.tf)

create_dns_zone:
	@echo "create_dns_zone"
	## [region_resources/06-dns.tf]

create_dns_ns_record: create_dns_zone
	@echo "create_dns_ns_record"
	## [region_resources/06-dns.tf]

role_assignment: dns_rbac subscription_rbac tfstate_rw-container_ro-rbac
	@echo "role_assignment"

dns_rbac:
	@echo "dns_rbac"
	## (_bootstrap/01-dns-rbac.tf)

subscription_rbac:
	@echo "subscription_rbac"
	## (_bootstrap/01-subscription-rbac.tf)

tfstate_rw-container_ro-rbac:
	@echo "subscription_rbac"
	## (_bootstrap/00-tfstate_rw-container_ro-rbac.tf)
	## should be removed when totally replacing tf2

generate_local_file:
	@echo "generate_local_file"
	## envrc-registry (overlay/00-arr.tf)
	## svc-envrcs (overlay/05-envrcs.tf)
	## cx-envrcs (overlay/05-envrcs.tf)
	## svc-envrcs-default (overlay/05-envrcs.tf)
	## cx-envrcs-default (overlay/05-envrcs.tf)
	## extra_env_rc (overlay/10-extra_envrc.tf)
	## acsrp_config (overlay/import_acsrp_configs.tf)
	## acsrp_config_admin (overlay/import_acsrp_configs.tf)
	## hcp_region_yaml (overlay/import_charts_configs.tf)
	## registry_yaml (overlay/import_charts_configs.tf)
	## rp_region_yaml (overlay/import_charts_configs.tf)
	## nginx_ingress_controller_yaml (overlay/import_charts_configs.tf)

	## envrc-registry (region_resources/00-acr.tf)
	## svc-envrcs (region_resources/.tf)
	## cx-envrcs (region_resources/05-envrcs.tf)
	## svc-envrcs-default (region_resources/05-envrcs.tf)
	## cx-envrcs-default (region_resources/05-envrcs.tf)
	## hcp_region_yaml (region_resources/04-charts_configs.tf)
	## rp_region_yaml (region_resources/04-charts_configs.tf)
	## registry_yaml (region_resources/04-charts_configs.tf)
	## nginx_ingress_controller_yaml (region_resources/04-charts_configs.tf)
	## acsrp_config ((region_resources/08-acsrp_configurations.tf)
	## acsrp_config_admin((region_resources/08-acsrp_configurations.tf)

create_hcp_svc_infrastructure:
	@echo "create_hcp_svc_infrastructure"
	## region_resources/02-hcp_svc_infrastructure.tf
	##   hcp_service
	##   keyvault_loader/generic-v2