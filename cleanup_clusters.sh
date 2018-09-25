#!/bin/bash
set +e

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CLUSTER1_ID="shriramr-c2"
CLUSTER2_ID="shriramr-c3"
ROOTCA_ID="shriramr-c1"

CLUSTER1_NAME="k1.${CLUSTER1_ID}.k8s.local"
CLUSTER2_NAME="k1.${CLUSTER2_ID}.k8s.local"
ROOTCA_NAME="k1.${ROOTCA_ID}.k8s.local"

ROOTCA_BUCKET="${ROOTCA_ID}-kops-state-store"
CLUSTER1_BUCKET="${CLUSTER1_ID}-kops-state-store"
CLUSTER2_BUCKET="${CLUSTER2_ID}-kops-state-store"

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

kops delete cluster --name ${ROOTCA_NAME} --state ${ROOTCA_STATE} --yes
kops delete cluster --name ${CLUSTER1_NAME} --state ${CLUSTER1_STATE} --yes
kops delete cluster --name ${CLUSTER2_NAME} --state ${CLUSTER2_STATE} --yes
aws s3api delete-bucket --bucket ${ROOTCA_BUCKET}
aws s3api delete-bucket --bucket ${CLUSTER1_BUCKET}
aws s3api delete-bucket --bucket ${CLUSTER2_BUCKET}

exit $success
