# Amazon CloudWatch Agent
## Introduction
This Amazon Cloud Watch instance deploys the amazon cloudwatch agent, which has been configured to scrape metrics from the built in prometheus instance of the OCP cluster and ship them to Amazon CloudWatch for aggregation.

## Credentials
AWS credentials are needed for the logs to appear in the correct account.

The method used within the pattern is to pull the credentials **file** (example below) from the vault, stored under vault path secrets/awscreds. The pulling is done by the external secrets operator which is preconfigured and installed on each cluster.

Example credentials file
```
[AmazonCloudWatchAgent]
aws_access_key_id=
aws_secret_access_key=
```

The corresponding IAM policy that needs toe be enabled against the credentials is CloudWatchAgentServerPolicy, without this the metrics wont be saved.

## Configuration
A configuratio file is used to inform the agent of what metrics to collect and where to send them. The clustername customization is done automatically, when the application is deployed, a job will run, find the cluster name and create the config map accordingly.

Region, this can be the same for all, but does not have to be.
```
    "agent": {
      "region": "ap-northeast-1",
      "debug": true
    },
```

Cluster Name, in the example below aws-tokyo should be changed per cluster, in both the cluster_name and log_group_name
```
 "metrics_collected": {
        "prometheus": {
          "cluster_name": "aws-tokyo",
          "log_group_name": "/aws/containerinsights/aws-tokyo/prometheus",
          "prometheus_config_path": "/etc/prometheusconfig/prometheus.yaml",
```

More metrics can be collected by manipulating the metric_declaration blocks