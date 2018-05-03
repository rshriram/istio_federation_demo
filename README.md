usage: ./run_demo_from_laptop.sh
prerequisites: kops, kubectl (1.9.x)

The `run_demo_from_laptop.sh` script creates two Kube clusters, one in us-east-1 and
another in us-west-1. It uses pre-created kops cluster configuration stored
in S3 (which essentially configures kops to deploy a cluster of 3 nodes,
with kubernetes 1.9.1+).

cluster1 folder has the Istio configuration needed to setup routing in
cluster1, along with a client application that is pre-injected with Istio
sidecar.

clsuter2 folder has the Istio configuration needed to setup routing in
cluster2, along with a server application that is pre-injected with Istio
sidecar.

The traffic flow:

`cluster1(client+proxy --> istio-egressgateway)-->cluster2(istio-ingressgateway-->proxy+server)`

cluster2's istio-ingressgateway is launched with a LoadBalancer, so that we
get a publicly routable address. This address is then used to configure the
external service in Cluster1.

There is no DNS setup required.

