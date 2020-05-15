#!/bin/bash

aks::e2e::resource::resource_group() {
    local name="$1"
    local location="$2"
    local tags="$3"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$location" ]]; then
        echo "LOCATION is empty"
        exit 1
    fi

    if [ $(az group exists --name "${name}") = false ]; then
        az group create --name "${name}" --location "${location}" --tags "${tags}"
    fi
}

aks::e2e::resource::storage_account() {
    local name="$1"
    local resource_group="$2"
    local location="$3"
    local access_tier="$4"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "RESROUCE GROUP is empty"
        exit 1
    fi

    if [[ -z "$location" ]]; then
        echo "LOCATION is empty"
        exit 1
    fi

    if [[ -z "$access_tier" ]]; then
        $access_tier="Hot"
    fi
    
    az storage account create --name "${name}" --resource-group "${resource_group}" --location "${location}" --kind StorageV2 --access-tier "${access_tier}" --sku Standard_LRS
}

aks::e2e::resource::storage_container() {
    local name="$1"
    local storage_account_name="$2"

    if [[ -z "$name" ]]; then
        echo "Name is empty"
        exit 1
    fi

    if [[ -z "$storage_account_name" ]]; then
        echo "Storage Account Name is empty"
        exit 1
    fi

    az storage container create --name "${name}" --account-name "${storage_account_name}"
}

aks::e2e::resource::storage_blob() {
    local name="$1"
    local storage_account_name="$2"
    local storage_container_name="$3"
    local path="$4"


    if [[ -z "$name" ]]; then
        echo "Container Name is empty"
        exit 1
    fi

    if [[ -z "$storage_account_name" ]]; then
        echo "Storage Account Name is empty"
        exit 1
    fi

    if [[ -z "$storage_container_name" ]]; then
        echo "Storage Container Name is empty"
        exit 1
    fi

    if [[ -z "$path" ]]; then
        echo "Path is empty"
        exit 1
    fi

    az storage blob upload --container-name "${storage_container_name}" --account-name "${storage_account_name}" --name "${name}" --file "${path}" --type block
}

aks::e2e::resource::key_vault() {
    local name="$1"
    local resource_group="$2"
    local location="$3"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "RESROUCE GROUP is empty"
        exit 1
    fi

    if [[ -z "$location" ]]; then
        echo "LOCATION is empty"
        exit 1
    fi

    az keyvault create --name "${name}" --resource-group "${resource_group}" --location "${location}" --sku premium --enabled-for-template-deployment true
}

aks::e2e::resource::key_vault_set_policy() {
    local name="$1"
    local object_id="$2"
    local key_permissions="$3"
    local secret_permissions="$4"
    local certificate_permissions="$5"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$object_id" ]]; then
        echo "Object ID is empty"
        exit 1
    fi

    az keyvault set-policy --name "${name}" --object-id "${object_id}" --key-permissions ${key_permissions} --certificate-permissions ${certificate_permissions} --secret-permissions ${secret_permissions}
}

aks::e2e::resource::key_vault_secret() {
    local name="$1"
    local vault_name="$2"
    local value="$3"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$vault_name" ]]; then
        echo "Vault Name is empty"
        exit 1
    fi

    if [[ -z "$value" ]]; then
        echo "Value is empty"
        exit 1
    fi

    az keyvault secret set --name "${name}" --vault-name "${vault_name}" --value "${value}"
}

aks::e2e::resource::key_vault_certificate() {
    local name="$1"
    local vault_name="$2"
    local policy_path="$3"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$vault_name" ]]; then
        echo "Vault Name is empty"
        exit 1
    fi

    if [[ -z "$policy_path" ]]; then
        echo "Policy Path is empty"
        exit 1
    fi

    az keyvault certificate create --name "${name}" --vault-name "${vault_name}" --policy @"${policy_path}"
}

aks::e2e::resource::cosmosdb_account() {
    local name="$1"
    local resource_group="$2"
    local location="$3"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "Resource Group is empty"
        exit 1
    fi

    if [[ -z "$location" ]]; then
        echo "Location is empty"
        exit 1
    fi

    az cosmosdb create --name "${name}" --resource-group "${resource_group}" --kind MongoDB --default-consistency-level Strong --locations regionName=${location} failoverPriority=0
}

aks::e2e::resource::sql_server() {
    local name="$1"
    local resource_group="$2"
    local location="$3"
    local user="$4"
    local password="$5"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "Resource Group is empty"
        exit 1
    fi

    if [[ -z "$location" ]]; then
        echo "Location is empty"
        exit 1
    fi

    az sql server create --name "${name}" --resource-group "${resource_group}" --location "${location}" --admin-user "${user}" --admin-password "${password}"
}

aks::e2e::resource::sql_database() {
    local name="$1"
    local resource_group="$2"
    local server="$3"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "Resource Group is empty"
        exit 1
    fi

    if [[ -z "$server" ]]; then
        echo "Server is empty"
        exit 1
    fi

    az sql db create --server "${server}" --name "${name}" --resource-group "${resource_group}" --edition Standard --service-objective S1
}

aks::e2e::resource::sql_firewall_rule() {
    local name="$1"
    local resource_group="$2"
    local server="$3"
    local start_ip_address="$4"
    local end_ip_address="$5"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "Resource Group is empty"
        exit 1
    fi

    if [[ -z "$server" ]]; then
        echo "Server is empty"
        exit 1
    fi

    az sql server firewall-rule create --name "${name}" --resource-group "${resource_group}" --server "${server}" --start-ip-address "${start_ip_address}" --end-ip-address "${end_ip_address}"
}

aks::e2e::resource::role_assignment() {
    local principal_id="$1"
    local scope="$2"
    local role_definition_name="$3"

    
    if [[ -z "$principal_id" ]]; then
        echo "Pricipal Id is empty"
        exit 1
    fi

    if [[ -z "$scope" ]]; then
        echo "Scope is empty"
        exit 1
    fi

    if [[ -z "$role_definition_name" ]]; then
        echo "Role Definition Name is empty"
        exit 1
    fi

    az role assignment create --role "${role_definition_name}" --assignee-object-id "${principal_id}" --scope "${scope}"
}

aks::e2e::resource::dns_zone() {
    local name="$1"
    local resource_group="$2"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "Resource Group is empty"
        exit 1
    fi

    az network dns zone create --name "${name}" --resource-group "${resource_group}"
}

aks::e2e::resource::dns_ns_record() {
    local name="$1"
    local resource_group="$2"
    local zone_name="$3"
    local nsdname="$4"

    if [[ -z "$name" ]]; then
        echo "NAME is empty"
        exit 1
    fi

    if [[ -z "$resource_group" ]]; then
        echo "Resource Group is empty"
        exit 1
    fi

    if [[ -z "$zone_name" ]]; then
        echo "Zone Name is empty"
        exit 1
    fi

    az network dns record-set ns add-record --zone-name "${zone_name}" --resource-group "${resource_group}" --record-set-name "${name}" --nsdname "${nsdname}" --ttl 300
}