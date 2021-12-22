#!/usr/bin/env bash
SECRETS=false

function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function kustomization () {
read -r -d  '' kustomization_yaml << EOM
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base/
  - ../../../base/

namespace: $VALUES_cluster-cluster
namePrefix: $VALUES_cluster

replacements:
  - source:
      kind: Namespace
      # need to leave it suffixed with -cluster
      name:  $VALUES_cluster-cluster
    targets:
      - select:
          kind: KlusterletAddonConfig 
        fieldPaths:
          - spec.clusterName
          - spec.clusterNamespace
      - select:
          kind: MachinePool 
        fieldPaths:
          - spec.clusterDeploymentRef.name
      - select:
          kind: ClusterDeployment 
        fieldPaths:
          - spec.platform.vsphere.cluster
      - select:
          kind: ManagedCluster 
        fieldPaths:
          - metadata.labels.name
      - select:
          kind: SealedSecret 
        fieldPaths:
          - spec.template.metadata.namespace
  - source:
      kind: SealedSecret
      name: $VALUES_cluster-pull-secret
    targets:
      - select:
          kind: ClusterDeployment
        fieldPaths:
         - spec.pullSecretRef.name
  - source:
      kind: SealedSecret
      name: $VALUES_cluster-vsphere-creds
    targets:
      - select:
          kind: ClusterDeployment
        fieldPaths:
         - spec.platform.vsphere.credentialsSecretRef.name
  - source:
      kind: SealedSecret
      name: $VALUES_cluster-vsphere-certs
    targets:
      - select:
          kind: ClusterDeployment
        fieldPaths:
         - spec.platform.vsphere.certificatesSecretRef.name
  - source:
      kind: SealedSecret
      name: $VALUES_cluster-install-config
    targets:
      - select:
          kind: ClusterDeployment
        fieldPaths:
         - spec.provisioning.installConfigSecretRef.name
  - source:
      kind: SealedSecret
      name: $VALUES_cluster-ssh-private-key
    targets:
      - select:
          kind: ClusterDeployment
        fieldPaths:
         - spec.provisioning.sshPrivateKeySecretRef.name
  - source:
      kind: Namespace 
    targets:
      - select:
          kind: Namespace
        fieldPaths:
         - metadata.annotations.openshift\.io/display-name

patches:
  - target: 
      group: hive.openshift.io
      version: v1
      kind: MachinePool 
    patch: |-
      - op: replace 
        path: /spec/platform/vsphere
        value: 
          cpus: $VALUES_workers__cpus
          coresPerSocket:  $VALUES_workers__cpus
          memoryMB:  $VALUES_workers__memoryMB
          osDisk:
            diskSizeGB: $VALUES_workers__diskGB
      - op: replace 
        path: /spec/replicas
        value: $VALUES_workers__count 

EOM
}

function vsph_install_config () {
read -r -d  '' install_config << EOM
apiVersion: v1
metadata:
  name: '$VALUES_cluster' 
baseDomain: $VALUES_provider__baseDomain
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: $VALUES_masters__count
  platform:
    vsphere:
      cpus: $VALUES_masters__cpus
      coresPerSocket:  $VALUES_masters__coresPerSocket
      memoryMB:  $VALUES_masters__memoryMB
      osDisk:
        diskSizeGB: $VALUES_masters__diskGB
compute:
- hyperthreading: Enabled
  name: 'worker'
  replicas: $VALUES_workers__count 
  platform:
    vsphere:
      cpus: $VALUES_workers__cpus
      coresPerSocket:  $VALUES_workers__cpus
      memoryMB:  $VALUES_workers__memoryMB
      osDisk:
        diskSizeGB: $VALUES_workers__diskGB
platform:
  vsphere:
    vCenter: $VALUES_provider__vcenter
    username: $VSPH_USER
    password: $VSPH_PASS
    datacenter: $VALUES_provider__datacenter
    defaultDatastore: $VALUES_provider__datastore
    cluster: $VALUES_cluster
    apiVIP: $VALUES_network__apiVIP
    ingressVIP: $VALUES_network_ingressVIP
    network: $VALUES_network__networkName
pullSecret: "" # skip, hive will inject based on it's secrets
sshKey: |-
    $SSH_PUB_KEY
EOM
}

#Begin program
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -o|--overlay)
      OVERLAY="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--secrets)
      SECRETS=true
      shift # past argument
      shift # past value
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

if [[ -f $OVERLAY/values.yaml  ]]; then
  #extract values from values.yaml
  eval $(parse_yaml $OVERLAY/values.yaml "VALUES_")
else 
  echo "no values.yaml found in overlay"
  exit 1
fi

if [[ $SECRETS = true ]] ; then

  if [[ -z ${VSPH_PASS} ]]; then
    echo "Please provide environment variable VSPH_PASS containing the vSphere passowrd"
    exit 1
  fi

  if [[ -z ${VSPH_USER} ]]; then
    echo "Please provide environment variable VSPH_PASS containing the vsphere user"
    exit 1
  fi

  if [[ -z ${SSH_PRIV_FILE} ]]; then
    echo "Please provide environment variable SSH_PRIV_FILE"
    exit 1
  fi

  if [[ -z ${SSH_PUB_FILE} ]]; then
    echo "Please provide environment variable SSH_PUB_FILE, containing the path to matching public ssh key matched to the private key"
    exit 1
  fi

  if [[ -z ${VSPH_CACERT_FILE} ]]; then
    echo "Please provide environment variable VSPH_CACERT_FILE, containing the path to matching public certificate for the vcenter server"
    exit 1
  fi

  if [[ -z ${PULL_SECRET} ]]; then
    echo "Please provide environment variable PULL_SECRET"
    exit 1
  fi

  SEALED_SECRET_NAMESPACE=${SEALED_SECRET_NAMESPACE:-sealed-secrets}
  SEALED_SECRET_CONTROLLER_NAME=${SEALED_SECRET_CONTROLLER_NAME:-sealed-secrets}


  #read in public ssh key
  ssh_pub_key=$(cat ${SSH_PUB_FILE})
  ssh_priv_key=$(cat ${SSH_PRIV_FILE})
  ca_cert=$(cat ${VSPH_CACERT_FILE})

  echo "Generate Install Config"
  vsph_install_config 

  # Encrypt the secret using kubeseal and private key from the cluster
  echo "Creating Secrets"
  ENC_INST_CFG=$(echo -n "$install_config" | kubeseal --raw --scope cluster-wide --name=$VALUES_cluster-install-config --controller-namespace $SEALED_SECRET_NAMESPACE --controller-name $SEALED_SECRET_CONTROLLER_NAME --from-file=/dev/stdin)
  ENC_VSPH_USER=$(echo -n ${VSPH_USER} | kubeseal --raw --scope cluster-wide --name=$VALUES_cluster-vsphere-creds  --controller-namespace $SEALED_SECRET_NAMESPACE --controller-name $SEALED_SECRET_CONTROLLER_NAME --from-file=/dev/stdin)
  ENC_VSPH_PASS=$(echo -n ${VSPH_PASS} | kubeseal --raw --scope cluster-wide --name=$VALUES_cluster-vsphere-creds  --controller-namespace $SEALED_SECRET_NAMESPACE --controller-name $SEALED_SECRET_CONTROLLER_NAME --from-file=/dev/stdin)
  ENC_PULL_SECRET=$(echo -n ${PULL_SECRET} | kubeseal --raw --scope cluster-wide --name=$VALUES_cluster-pull-secret  --controller-namespace $SEALED_SECRET_NAMESPACE --controller-name $SEALED_SECRET_CONTROLLER_NAME --from-file=/dev/stdin)
  ENC_SSH_PRIV=$(cat ${SSH_PRIV_FILE} | kubeseal --raw --scope cluster-wide --name=$VALUES_cluster-ssh-private-key   --controller-namespace $SEALED_SECRET_NAMESPACE --controller-name $SEALED_SECRET_CONTROLLER_NAME --from-file=/dev/stdin)
  ENC_VSPH_PUB_CA=$(cat ${VSPH_CACERT_FILE} | kubeseal --raw --scope cluster-wide --name=$VALUES_cluster-vsphere-certs   --controller-namespace $SEALED_SECRET_NAMESPACE --controller-name $SEALED_SECRET_CONTROLLER_NAME --from-file=/dev/stdin)

  echo "Updating values file with encrypted secrets"
  sed -i '' -e 's#.*username.*$#    username: '$ENC_VSPH_USER'#g' base/secret-vsphere-creds.yaml
  sed -i '' -e 's#.*password.*$#    password: '$ENC_VSPH_PASS'#g' base/secret-vsphere-creds.yaml
  sed -i '' -e 's#.*\.dockerconfigjson:.*$#    \.dockerconfigjson: '$ENC_PULL_SECRET'#g' ../base/secret-pull-secret.yaml
  sed -i '' -e 's#.*ssh-privatekey:.*$#    ssh-privatekey: '$ENC_SSH_PRIV'#g' ../base/secret-ssh-private-key.yaml
  sed -i '' -e 's#.*install-config\.yaml.*$#   install-config\.yaml: '$ENC_INST_CFG'#g' base/secret-install-config.yaml
  sed -i '' -e 's#.*\.cacert.*$#    \.cacert: '$ENC_VSPH_PUB_CA'#g' base/secret-vsphere-certs.yaml

fi
  
echo "Generate kustomization.yaml"
kustomization
echo "$kustomization_yaml" > $OVERLAY/kustomization.yaml