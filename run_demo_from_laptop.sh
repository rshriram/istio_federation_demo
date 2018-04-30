#!/bin/bash
set -e

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CLUSTER1_NAME="cluster1.k8s.local"
CLUSTER2_NAME="cluster2.k8s.local"

CLUSTER1_STATE="s3://cluster1-global-state-store"
CLUSTER2_STATE="s3://cluster2-global-state-store"

CLUSTER1_ZONE="us-east-1a"
CLUSTER2_ZONE="us-west-1a"

kops create cluster --name ${CLUSTER1_NAME} \
  --state ${CLUSTER1_STATE} --zones ${CLUSTER1_ZONE} \
  --node-count=3
kops update cluster ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes

kops create cluster --name ${CLUSTER2_NAME} \
  --state ${CLUSTER2_STATE} --zones ${CLUSTER2_ZONE} \
  --node-count=3
kops update cluster ${CLUSTER2_NAME} --state ${CLUSTER2_STATE} --yes

sleep 300 # or run kops validate cluster

kops validate cluster --name $CLUSTER1_NAME --state ${CLUSTER1_STATE}
kops validate cluster --name $CLUSTER2_NAME --state ${CLUSTER2_STATE}

kubectl --context ${CLUSTER1_NAME} get nodes
kubectl --context ${CLUSTER2_NAME} get nodes

# Install CoreDNS. All queries to *.global will resolve to 127.0.0.1
# To change the domain, tweak coredns.yaml
kubectl --context ${CLUSTER1_NAME} apply -f coredns.yaml
kubectl --context ${CLUSTER1_NAME} delete --namespace=kube-system deployment kube-dns

kubectl --context ${CLUSTER2_NAME} apply -f coredns.yaml
kubectl --context ${CLUSTER2_NAME} delete --namespace=kube-system deployment kube-dns

kubectl --context ${CLUSTER1_NAME} apply -f istio.yaml
kubectl --context ${CLUSTER2_NAME} apply -f istio.yaml

sleep 300 # NEED A WAY TO TEST IF ALL ISTIO COMPONENTS ARE UP

cluster2_gateway=`kubectl --context ${CLUSTER2_NAME} get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

sed -e s/__REPLACEME__/${cluster2_gateway}/g ${SCRIPTDIR}/cluster1/external-service.yaml | kubectl --context ${CLUSTER1_NAME} apply -f -
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/cluster1/egressgateway.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/cluster1/rule-route-via-egressgateway.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/cluster1/client.yaml

kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/cluster2/ingressgateway.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/cluster2/server.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/cluster2/rule-ingressgateway.yaml

sleep 30 #for things to settle
clientPod=`kubectl --context ${CLUSTER1_NAME} get po -l app=client -o jsonpath='{.items[0].metadata.name}'`

# Call cluster2's service from cluster1. Use dummy IP 1.1.1.1 to skip DNS resolution issue.
output=`kubectl --context ${CLUSTER1_NAME} exec -it $clientPod -c client -- curl http://server.cluster2.global/helloworld`
success=$?

kops delete cluster --name ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes
kops delete cluster --name ${CLUSTER2_NAME} --state ${CLUSTER2_STATE} --yes

echo "Test output for call from cluster1 to cluster2: $output"
exit $success
