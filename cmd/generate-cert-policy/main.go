package main

import (
	"encoding/json"
	"io/ioutil"

	"github.com/Azure/azure-sdk-for-go/services/keyvault/v7.0/keyvault"
	"github.com/Azure/go-autorest/autorest/to"
)

func main() {
	policy := keyvault.CertificatePolicy{
		IssuerParameters: &keyvault.IssuerParameters{
			Name: to.StringPtr("abc"),
		},
		KeyProperties: &keyvault.KeyProperties{
			KeySize: to.Int32Ptr(4096),
		},
	}

	file, _ := json.MarshalIndent(policy, "", " ")

	_ = ioutil.WriteFile("test.json", file, 0644)
}
