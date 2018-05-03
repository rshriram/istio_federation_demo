usage: ./run_demo_from_laptop.sh
prerequisites: kops, kubectl (1.9.x)

The `run_demo_from_laptop.sh` script creates two Kube clusters in AWS.

The traffic flow:

`cluster1(client+proxy --> istio-egressgateway)-->cluster2(istio-ingressgateway-->proxy+server)`

cluster2's istio-ingressgateway is launched with a LoadBalancer, so that we
get a publicly routable address. This address is then used to configure the
external service in Cluster1.

There is no DNS setup required.

