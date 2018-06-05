usage: ./run_demo_from_laptop.sh
prerequisites: kops, kubectl (1.9.x)

The `run_demo_from_laptop.sh` script creates two Kube clusters in AWS.

The traffic flow (with TLS):

`cluster1(client+proxy --> istio-egressgateway)-->cluster2(istio-ingressgateway-->proxy+server)`

cluster2's istio-ingressgateway is launched with a LoadBalancer, so that we
get a publicly routable address. This address is then used to configure the
external service in Cluster1.

There is no DNS setup required. A simple CoreDNS plugin is used to resolve
all hosts in the *.global domain to an invalid IP (1.1.1.1). Traffic from
the app is trapped by the sidecar, which routes it based on the HTTP host.

The client in cluster1 calls http://server2.cluster.global, which gets routed from the
local proxy to the local egress-gateway. From the egress gateway the
request traverses to the remote ingress gateway in cluster2, which then forwards the
request to the appropriate backend in cluster2.

TLS setup: A separate root CA cluster issues/rotates certs of cluster local
CAs. This allows cross cluster communication using mutual TLS, as there is
a shared root of trust. Within a cluster, istio mTLS authentication is used
to secure traffic between two endpoints.
