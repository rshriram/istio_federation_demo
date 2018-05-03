#!/bin/bash
set -e

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CLUSTER1_NAME="shriramr-c1.k8s.local"
CLUSTER2_NAME="shriramr-c2.k8s.local"

CLUSTER1_BUCKET="shriramr-c1-kops-state-store"
CLUSTER2_BUCKET="shriramr-c2-kops-state-store"
CLUSTER1_STATE="s3://${CLUSTER1_BUCKET}"
CLUSTER2_STATE="s3://${CLUSTER2_BUCKET}"

CLUSTER1_REGION="us-east-2"
CLUSTER2_REGION="us-east-2"

# a indicates AWS
KOPS_C1_ZONE="${CLUSTER1_REGION}a"
KOPS_C2_ZONE="${CLUSTER2_REGION}a"

#aws s3api create-bucket --bucket ${CLUSTER1_BUCKET} --region ${CLUSTER1_REGION} --create-bucket-configuration LocationConstraint=${CLUSTER1_REGION}
#aws s3api create-bucket --bucket ${CLUSTER2_BUCKET} --region ${CLUSTER2_REGION} --create-bucket-configuration LocationConstraint=${CLUSTER2_REGION}

kops create cluster --name ${CLUSTER1_NAME} \
  --state ${CLUSTER1_STATE} --zones ${KOPS_C1_ZONE} \
  --node-count=2
kops update cluster ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes

kops create cluster --name ${CLUSTER2_NAME} \
  --state ${CLUSTER2_STATE} --zones ${KOPS_C2_ZONE} \
  --node-count=2
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

cluster1_gateway=`kubectl --context ${CLUSTER1_NAME} get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
cluster2_gateway=`kubectl --context ${CLUSTER2_NAME} get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

sed -e s/__REPLACEME__/${cluster1_gateway}/g ${SCRIPTDIR}/route-rules/cluster1-service-entry.yaml | kubectl --context ${CLUSTER1_NAME} apply -f -
sed -e s/__REPLACEME__/${cluster2_gateway}/g ${SCRIPTDIR}/route-rules/cluster2-service-entry.yaml | kubectl --context ${CLUSTER1_NAME} apply -f -
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/ingress-gateway.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/egress-gateway.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/common-virtual-service.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/client.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/server.yaml

sed -e s/__REPLACEME__/${cluster1_gateway}/g ${SCRIPTDIR}/route-rules/cluster1-service-entry.yaml | kubectl --context ${CLUSTER2_NAME} apply -f -
sed -e s/__REPLACEME__/${cluster2_gateway}/g ${SCRIPTDIR}/route-rules/cluster2-service-entry.yaml | kubectl --context ${CLUSTER2_NAME} apply -f -
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/ingress-gateway.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/egress-gateway.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/common-virtual-service.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/client.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/server.yaml

kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/cluster2-inbound-virtual-service.yaml

sleep 30 #for things to settle
clientPod=`kubectl --context ${CLUSTER1_NAME} get po -l app=client -o jsonpath='{.items[0].metadata.name}'`

# Call cluster2's service from cluster1. Use dummy IP 1.1.1.1 to skip DNS resolution issue.
output=`kubectl --context ${CLUSTER1_NAME} exec -it $clientPod -c client -- curl http://server.cluster2.global/helloworld`
success=$?

#set +e
#kops delete cluster --name ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes
#kops delete cluster --name ${CLUSTER2_NAME} --state ${CLUSTER2_STATE} --yes
#aws s3api delete-bucket --bucket ${CLUSTER1_BUCKET}
#aws s3api delete-bucket --bucket ${CLUSTER2_BUCKET}

echo "Test output for call from cluster1 to cluster2: $output"
exit $success
