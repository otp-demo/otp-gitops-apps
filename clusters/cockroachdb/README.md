# CockroachDB Deployment Notes

## Cluster Selector

Currently, to add (or remove) clusters you wish to deploy (or destroy) cockroachdb to. You need to first remove the label from the ManagedCluster CRD with key and value workload and cockroachdb respectively. The CRD's in question could be found in the Demo Hub Cluster. Currently, this is a manual process. I made an application out of this to automate it but haven't merged it yet due to the code freeze.

## Files to modify

Following the above, you need to modify the contents of the following files (Note the path is relative to the root directory of the repository):

1) clusters/cockroachdb-postdeploy-commands/values.yaml
2) clusters/cockroachdb-deploy/chart/values.yaml
3) clusters/cockroachdb-deploy/values.yaml

The first file contains an entry called cdbClusters containing a list of clusters. Simply add and remove the clusters.
The second file contains a key called "join" (line 62). Each line within the join command has the following format:

cockroachdb-X.clusterNameHere.cockroachdb.multi-cluster-cockroachdb.svc.clusterset.local (X goes from 0 to 2 as the replica count of the stateful set is set to 3).

For example, if you want to add a cluster with name test, you would add three entries as shown below. See the note on X above:

cockroachdb-X.test.cockroachdb.multi-cluster-cockroachdb.svc.clusterset.local

On a similar token, if you wish to remove a cluster named testRemove, simply search for the three entries containing testRemove and delete corresponding lines.

Finally, the third file contains a key entry called clusterNames. Again, add and remove the clusters from here. 

Save your changes, git add and git push.

## Argo

For testing purposes, I have, for the time being, removed automated sync from the respective Argo Applications. There are two applications and can be found at the following URL's:

1) https://openshift-gitops-cntk-server-openshift-gitops.my-hub-cluster-76297f3ac7813438ee95ea76b1d62fd4-0000.au-syd.containers.appdomain.cloud/applications/cockroachdb?resource=
2) https://openshift-gitops-cntk-server-openshift-gitops.my-hub-cluster-76297f3ac7813438ee95ea76b1d62fd4-0000.au-syd.containers.appdomain.cloud/applications/cockroachdb-configure?resource=

In the first link, press the sync button up the top with the following options:

1) Replace
2) Force

You may need to do this two times as it will fail the first time trying to delete resources which are already deleted.

In the second link, delete all the jobs (the blocks with job) manually. This will delete the corresponding pods they spawn. Then re-sync the app with the default options. 

Once testing and validation for cockroachdb is complete, I plan to configure the application to auto synchronize and heal. But I'm leaving it as such for now.

The jobs take about 3-4 minutes to complete. Once they are all done. We should be in order.