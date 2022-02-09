# Vault PKI & Cert-Manager Integration
Vault can act as a certificate authortity for creating Public Key Infrastrucutre (PKI) certificates on demand, it can also be integrated with cert-manager to be able to do that process from kubernets manifests. The resulting certificates and keys will be stored in a secret in the desired namespace.

Currently the process is not automated, the following steps can be used to create the vault configuration and then the coresponding cert-manager ClusterIssuer configuration. 
The examples below are using the Vault CLI, you can either download the vault CLI and use it locally on your computer. 

To make it easier its best to eithier set enviornment variables; 

```
export VAULT_ADDR=https://vault.example.com
export VAULT_TOKEN=s.42rwlfknsdf-02i342;l4m23
```

Or login
```
vault login -address https://vault.example.com
``` 


Note: This configruation can also be done via the Vault ui, this however is not covered in this guide, but the general steps can be followed

# Setup
## Enable Vault PKI
These steps **only** need to be perfomed once per vault installation.


Enable vault PKI mode and set some basic parameters.
```
vault secrets enable -tls-skip-verify pki
vault secrets tune -tls-skip-verify -max-lease-ttl=87600h pki
vault write -tls-skip-verify pki/root/generate/internal common_name=cert-manager.cluster.local ttl=87600h
```

The next steps might need to be adjusted for your installation, espically the allowed domains section.
```
vault write -tls-skip-verify pki/config/urls issuing_certificates="http://vault.vault.svc:8200/v1/pki/ca" crl_distribution_points="http://vault.vault.svc:8200/v1/pki/crl"
vault write -tls-skip-verify pki/roles/cert-manager allowed_domains=svc,svc.cluster.local,svc.clusterset.local,node,root,yugabyte,keycloak,vault,cockroachdb,example.com allow_bare_domains=true allow_subdomains=true allow_localhost=false enforce_hostnames=false
```

Finally create the policy for the cert-manager user
The cert-manager-policy.hcl
```
# add full access to the cert-manager cert issuer
path "pki/issue/cert-manager" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/sign/cert-manager" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

And to apply it.

```
vault policy write -tls-skip-verify cert-manager ./vault/cert-manager-policy.hcl
```


## Configure Vault for Kuberentes Authentication
For each cluster that will be accessing vault the following steps configurae Kuberentes token authentication, which Vault has built in. This is configured per cluster, hence the following steps need to be performed for each cluster, some information needs to be gathered from that cluster too such as service account tokens.

Note some of these steps assume vault is also installed on the cluster, this should also be possible to setup with out vault installed on the cluster.

```
# get the name of the cluster and remove the unique id stuff at the end e.g. aws-cluster-shared-2-252ds --> aws-cluster-shared-2
export clusterid=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' | sed 's/-[^-]*$//g' )

#get the sa_account token for vault to extract kubernetes ca??
export sa_secret_name=$(oc get sa vault -n vault -o jsonpath='{.secrets[*].name}' | grep -o '\b\w*\-token-\w*\b')
oc get secret ${sa_secret_name} -n vault -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca.crt

#get the api url of the cluster we are running on
export api_url=$(oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}')

#create the auth path for the current cluster
vault auth enable -tls-skip-verify -path=kubernetes-${clusterid} kubernetes 

#configure token authentication, using the vault service account token and certificate extracted earlier.
vault write -tls-skip-verify auth/kubernetes-${clusterid}/config token_reviewer_jwt="$(oc serviceaccounts get-token vault -n vault)" kubernetes_host=${api_url} kubernetes_ca_cert=@/tmp/ca.crt

#configure the cert-manager role for the given cluster
vault write -tls-skip-verify auth/kubernetes-${clusterid}/role/cert-manager bound_service_account_names=default bound_service_account_namespaces=cert-manager policies=default,cert-manager
```


## Configure the ClusterIssuer 
The following steps are used to configure the ClusterIssuer configuration of cert-manager, these needs be done in conjuntion with the procedure above per cluster.

```
#extract the vault tls ca
export vault_ca=$(oc get secret vault-tls -n vault -o jsonpath='{.data.ca\.crt}')

#get the default service account token
export cm_sa_secret_name=$(oc get sa default -n cert-manager -o jsonpath='{.secrets[*].name}' | grep -o '\b\w*\-token-\w*\b')
```

Template  for creating the ClusterIssuer, consuming the root CA and secret name.
```
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-pki
spec:
  vault:
    path: pki/sign/cert-manager
    server: https://vault.global.basedomain.com:443
    caBundle: ${vault_ca}
    auth:
      kubernetes:
        role: cert-manager
        mountPath: /v1/auth/kubernetes-${clusterid}
        secretRef:
          name: ${cm_sa_secret_name}
          key: token
```

To apply

```
envsubst < vault-issuer.yaml | oc apply -f - -n cert-manager
```