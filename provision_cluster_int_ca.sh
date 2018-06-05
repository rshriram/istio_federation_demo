#!/bin/bash
set -e

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

ROOTCA_NAME=$1
CLUSTER_NAME=$2
CLUSTER_ID=$3

SERVICE_ACCOUNT="istio-citadel-service-account-${CLUSTER_ID}"
NAMESPACE="istio-system"
CERT_NAME="istio.${SERVICE_ACCOUNT}"

B64_DECODE=${BASE64_DECODE:-base64 --decode}
mkdir -p /tmp/ca/${CLUSTER_NAME}
DIR="/tmp/ca/${CLUSTER_NAME}"

kubectl --context ${ROOTCA_NAME} get -n ${NAMESPACE} secret $CERT_NAME -o jsonpath='{.data.root-cert\.pem}' | $B64_DECODE   > ${DIR}/root-cert.pem
kubectl --context ${ROOTCA_NAME} get -n ${NAMESPACE} secret $CERT_NAME -o jsonpath='{.data.cert-chain\.pem}' | $B64_DECODE  > ${DIR}/cert-chain.pem
kubectl --context ${ROOTCA_NAME} get -n ${NAMESPACE} secret $CERT_NAME -o jsonpath='{.data.key\.pem}' | $B64_DECODE   > ${DIR}/ca-key.pem
cp ${DIR}/cert-chain.pem ${DIR}/ca-cert.pem

# validate
openssl x509 -in ${DIR}/cert-chain.pem -noout -text | grep "URI:spiffe://cluster.local/ns/${NAMESPACE}/sa/${SERVICE_ACCOUNT}"
if [ $? -ne 0 ]; then
    echo "failed to validate intermediate CA cert for ${CLUSTER_NAME}"
    exit 1
fi

openssl x509 -in ${DIR}/cert-chain.pem -noout -text | grep "CA:TRUE"
if [ $? -ne 0 ]; then
    echo "failed to validate intermediate CA cert for ${CLUSTER_NAME}"
    exit 1
fi

kubectl --context ${CLUSTER_NAME} create secret generic cacerts -n istio-system \
        --from-file=${DIR}/ca-cert.pem --from-file=${DIR}/ca-key.pem \
        --from-file=${DIR}/root-cert.pem --from-file=${DIR}/cert-chain.pem

exit 0
