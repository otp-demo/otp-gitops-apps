# Openshit Logging
Openshift logging provide both the tools to collect logs from  a cluster and then to either store and process them locally using elasticsearch and kibana. However this does not scale all that well when my clusters are used or they are ephemeral. 
The solution is aggregate logs to a central store outside the clusters. Openshift supports a number of different forwarding backends.
 - elasticsearch
 - syslog
 - cloudwatch
 - loki
 - kafka
 - fluentdForward

## AWS Cloudwatch
Currently within the OTP pattern openshift-logging is setup to forward logs to AWS cloudwatch. This is automated, the only thing that needs to be configured is secrets in vault and the logging region.

For the ClusterLogForwarder to work, a ClusterLog Manifest also needs to be created to enable fluentd (as a Daemonset) to collect the logs from each node for the Log Forwarder to then on forward to the external logging system.


```
apiVersion: "logging.openshift.io/v1"
kind: "ClusterLogging"
metadata:
  name: "instance"
  namespace: "openshift-logging"
spec:
  managementState: "Managed"
  collection:
    logs:
      type: "fluentd"
      fluentd: {}
```

ClusterLogForwarder to forward the logs to cloudwatch
```
apiVersion: "logging.openshift.io/v1"
kind: ClusterLogForwarder
metadata:
  name: instance 
  namespace: openshift-logging 
spec:
  outputs:
   - name: cw 
     type: cloudwatch 
     cloudwatch:
       groupBy: namespaceName
       region: ap-southeast-2
     secret:
        name: aws-credentials 
  pipelines:
    - name: infra-logs 
      inputRefs: 
        - infrastructure
        - audit
        - application
      outputRefs:
        - cw 
```

Refer to [OpenShift Logging](https://docs.openshift.com/container-platform/4.8/logging/cluster-logging-external.html) documentation for more information.

## Secrets
External secrets are used in conjunction with vault to centralise and distribute 1 set of secrets to all clusters. 

The following manifest access vault to retrieve secrets from the Key Value path of secrets/awscreds

```
---
apiVersion: external-secrets.io/v1alpha1
kind: ExternalSecret
metadata:
  name: aws-credentials
  namespace: openshift-logging 
spec:
  refreshInterval: "10m"
  secretStoreRef:
    name: secretstore-vault
    kind: ClusterSecretStore
  target:
    name: aws-credentials
  data:
  - secretKey: aws_access_key_id 
    remoteRef:
      key: secrets/awscreds
      property: aws_access_key_id
  - secretKey: aws_secret_access_key
    remoteRef:
      key: secrets/awscreds
      property: aws_secret_access_key
```

Currently secret creation within vault is not automated and will need to be performed manually. The following will create the matching secrets via CLI.

```
vault kv put -tls-skip-verify secrets/awscreds aws_secret_access_key=<ACCESS_KEY>
vault kv put -tls-skip-verify secrets/awscreds aws_access_key_id=<ACCESS_ID>
```