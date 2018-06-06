A simple demonstration of cross cluster communication with Istio using
Istio gateways. The two Istio clusters could be in same or different region
or on-prem/off-prem or could even be using different platforms (e.g., K8S,
and CF).

![Traffic flow across clusters with end-to-end mTLS][Federation-setup]

The operator explicitly exposes one or more services in a cluster under a
common DNS suffix (e.g., *.global), via the Ingress gateway. Access to
remote clusters can be granted by adding an Istio ServiceEntry object that
points to the respective remote cluster's ingress gateway for all hosts
associated with the remote cluster.

Routing rules (virtual services) are setup such that traffic from a cluster
to a remote cluster always traverses through the local egress
gateway. Funneling all egress traffic through a dedicated egress gateway
simplifies policy enforcement, traffic scrubbing, etc.

Even though custom DNS names are used here, there is no additional DNS
setup required. Core DNS resolves all hosts in *.global to an invalid IP
(e.g., 1.1.1.1), allowing traffic to exit the application and be captured
by the sidecar. Once the traffic reaches the sidecar, routing is done
through HTTP Authority headers or SNI names.

For example, the client (curl command) in cluster1 calls
http://server2.cluster.global, which gets routed from the local proxy to
the local egress-gateway. From the egress gateway the request traverses to
the remote ingress gateway in cluster2, which then forwards the request to
the appropriate backend in cluster2.

A separate root CA cluster issues/rotates certs of cluster local CAs. This
allows cross cluster communication using mutual TLS, as there is a shared
root of trust. Within a cluster, istio mTLS authentication is used to
secure traffic between two endpoints.

[Federation-setup]: Federation-setup.png "Cross cluster communication using Istio Gateways"
