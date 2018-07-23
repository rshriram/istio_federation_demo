#!/bin/bash
set -e

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CLUSTER1_ID="shriramr-test-c1"
CLUSTER2_ID="shriramr-test-c2"
ROOTCA_ID="shriramr-root-ca"

CLUSTER1_NAME="${CLUSTER1_ID}.k8s.local"
CLUSTER2_NAME="${CLUSTER2_ID}.k8s.local"
ROOTCA_NAME="${ROOTCA_ID}.k8s.local"

ROOTCA_BUCKET=${ROOTCA_ID}
CLUSTER1_BUCKET=${CLUSTER1_ID}
CLUSTER2_BUCKET=${CLUSTER2_ID}

ROOTCA_STATE="s3://${ROOTCA_BUCKET}"
CLUSTER1_STATE="s3://${CLUSTER1_BUCKET}"
CLUSTER2_STATE="s3://${CLUSTER2_BUCKET}"

ROOTCA_REGION="us-east-2"
CLUSTER1_REGION="us-east-2"
CLUSTER2_REGION="us-east-2"

# a indicates AWS
KOPS_ROOTCA_ZONE="${ROOTCA_REGION}a"
KOPS_C1_ZONE="${CLUSTER1_REGION}a"
KOPS_C2_ZONE="${CLUSTER2_REGION}a"

aws s3api create-bucket --bucket ${ROOTCA_BUCKET} --region ${ROOTCA_REGION} --create-bucket-configuration LocationConstraint=${ROOTCA_REGION}
aws s3api create-bucket --bucket ${CLUSTER1_BUCKET} --region ${CLUSTER1_REGION} --create-bucket-configuration LocationConstraint=${CLUSTER1_REGION}
aws s3api create-bucket --bucket ${CLUSTER2_BUCKET} --region ${CLUSTER2_REGION} --create-bucket-configuration LocationConstraint=${CLUSTER2_REGION}

kops create cluster --name ${ROOTCA_NAME} \
  --state ${ROOTCA_STATE} --zones ${KOPS_ROOTCA_ZONE} \
  --node-count=1
kops update cluster ${ROOTCA_NAME} --state ${ROOTCA_STATE} --yes

kops create cluster --name ${CLUSTER1_NAME} \
  --state ${CLUSTER1_STATE} --zones ${KOPS_C1_ZONE} \
  --node-count=3
kops update cluster ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes

kops create cluster --name ${CLUSTER2_NAME} \
  --state ${CLUSTER2_STATE} --zones ${KOPS_C2_ZONE} \
  --node-count=3
kops update cluster ${CLUSTER2_NAME} --state ${CLUSTER2_STATE} --yes

sleep 300 # or run kops validate cluster

kops validate cluster --name $ROOTCA_NAME --state ${ROOTCA_STATE}
kops validate cluster --name $CLUSTER1_NAME --state ${CLUSTER1_STATE}
kops validate cluster --name $CLUSTER2_NAME --state ${CLUSTER2_STATE}

kubectl --context ${ROOTCA_NAME} get nodes
kubectl --context ${CLUSTER1_NAME} get nodes
kubectl --context ${CLUSTER2_NAME} get nodes

# # Install the ROOT CA
kubectl --context ${ROOTCA_NAME} apply -f rootca.yaml
rootca_host=`kubectl --context ${ROOTCA_NAME} get service standalone-citadel -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

kubectl --context ${ROOTCA_NAME} -n istio-system create serviceaccount istio-citadel-service-account-${CLUSTER1_ID}
kubectl --context ${ROOTCA_NAME} -n istio-system create serviceaccount istio-citadel-service-account-${CLUSTER2_ID}

# Install CoreDNS. All queries to *.global will resolve to 127.0.0.1
# To change the domain, tweak coredns.yaml
kubectl --context ${CLUSTER1_NAME} apply -f coredns.yaml
kubectl --context ${CLUSTER1_NAME} delete --namespace=kube-system deployment kube-dns
kubectl --context ${CLUSTER1_NAME} create namespace istio-system
${SCRIPTDIR}/provision_cluster_int_ca.sh $ROOTCA_NAME $CLUSTER1_NAME $CLUSTER1_ID

kubectl --context ${CLUSTER2_NAME} apply -f coredns.yaml
kubectl --context ${CLUSTER2_NAME} delete --namespace=kube-system deployment kube-dns
kubectl --context ${CLUSTER2_NAME} create namespace istio-system
${SCRIPTDIR}/provision_cluster_int_ca.sh $ROOTCA_NAME $CLUSTER2_NAME $CLUSTER2_ID

sed -e "s/__CLUSTERNAME__/${CLUSTER1_ID}/g;s/__ROOTCA_HOST__/${rootca_host}/g" istio.yaml | kubectl --context ${CLUSTER1_NAME} apply -f -
sed -e "s/__CLUSTERNAME__/${CLUSTER2_ID}/g;s/__ROOTCA_HOST__/${rootca_host}/g" istio.yaml | kubectl --context ${CLUSTER2_NAME} apply -f -

sleep 300 # NEED A WAY TO TEST IF ALL ISTIO COMPONENTS ARE UP

cluster1_gateway=`kubectl --context ${CLUSTER1_NAME} get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
cluster2_gateway=`kubectl --context ${CLUSTER2_NAME} get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`

sed -e s/__REPLACEME__/${cluster1_gateway}/g ${SCRIPTDIR}/route-rules/cluster1-service-entry.yaml | kubectl --context ${CLUSTER1_NAME} apply -f -
sed -e s/__REPLACEME__/${cluster2_gateway}/g ${SCRIPTDIR}/route-rules/cluster2-service-entry.yaml | kubectl --context ${CLUSTER1_NAME} apply -f -
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/ingress-gateway.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/egress-gateway.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/common-virtual-service.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/common-destination-rule.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/route-rules/egressgateway-destination-rule.yaml
kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/client.yaml
#kubectl --context ${CLUSTER1_NAME} apply -f ${SCRIPTDIR}/server.yaml

sed -e s/__REPLACEME__/${cluster1_gateway}/g ${SCRIPTDIR}/route-rules/cluster1-service-entry.yaml | kubectl --context ${CLUSTER2_NAME} apply -f -
sed -e s/__REPLACEME__/${cluster2_gateway}/g ${SCRIPTDIR}/route-rules/cluster2-service-entry.yaml | kubectl --context ${CLUSTER2_NAME} apply -f -
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/ingress-gateway.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/egress-gateway.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/common-virtual-service.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/common-destination-rule.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/egressgateway-destination-rule.yaml
#kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/client.yaml
kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/server.yaml

kubectl --context ${CLUSTER2_NAME} apply -f ${SCRIPTDIR}/route-rules/cluster2-inbound-virtual-service.yaml

sleep 30 #for things to settle
clientPod=`kubectl --context ${CLUSTER1_NAME} get po -l app=client -o jsonpath='{.items[0].metadata.name}'`

# Call cluster2's service from cluster1. Use dummy IP 1.1.1.1 to skip DNS resolution issue.
output=`kubectl --context ${CLUSTER1_NAME} exec -it $clientPod -c client -- curl -s -o /dev/null -I -w "%{http_code}" http://server.cluster2.global/helloworld`
success=0
if [ "$output" != "200" ]; then
    echo "Failed to reach remote server server.cluster2.global"
    success=1
else
    echo "Successfully connnected to remote server server.cluster2.global"
    success=0
fi

set +e
kops delete cluster --name ${ROOTCA_NAME} --state ${ROOTCA_STATE} --yes
kops delete cluster --name ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes
kops delete cluster --name ${CLUSTER2_NAME} --state ${CLUSTER2_STATE} --yes
aws s3api delete-bucket --bucket ${ROOTCA_BUCKET}
aws s3api delete-bucket --bucket ${CLUSTER1_BUCKET}
aws s3api delete-bucket --bucket ${CLUSTER2_BUCKET}

exit $success
