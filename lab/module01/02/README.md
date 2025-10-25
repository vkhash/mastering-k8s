# Building Kubernetes Control Plane

This guide's variant builds a Kubernetes control plane using `staticPods` resource (located in `/etc/kubernetes/manifests`). Local `setup.sh` script is based on `setup.sh` in project's root directory.

Specifically this variant of `setup.sh` does not start etcd, kube-apiserver, kube-controller-manager and kube-scheduler but relies on kubelet to start this resources (located in `/etc/kubernetes/manifests/`).

## Creating debug container example
```bash
export MY_NODE=$(sudo kubebuilder/bin/kubectl get nodes -oname | cut -d / -f 2)
export DEBUG_TOUT_SECONDS=45
export OUTPUT_LOCATION=$(pwd)
# run perf for $DEBUG_TOUT_SECONDS and save .svg in host /tmp/flame.svg directory
CMD_OUTPUT=`kubebuilder/bin/kubectl debug node/$MY_NODE --image=verizondigital/kubectl-flame:v0.2.4-perf --profile=sysadmin --env DEBUG_TOUT_SECONDS=$DEBUG_TOUT_SECONDS,OUTPUT_LOCATION=$OUTPUT_LOCATION -- sh -c "timeout $DEBUG_TOUT_SECONDS /app/perf record -F 99 -o /tmp/perf.data -g -p $(pgrep -f kube-apiserver); /app/perf script -i /tmp/perf.data | /app/FlameGraph/stackcollapse-perf.pl | /app/FlameGraph/flamegraph.pl > /host/$OUTPUT_LOCATION/flame.svg"`

sleep $(($DEBUG_TOUT_SECONDS + 15))
echo $CMD_OUTPUT | awk '{print $4}' | xargs kubebuilder/bin/kubectl delete pods
```

### Note
configuring control-plane with option `--cloud-provider=external` will add a special taint to the node if no cloud-provider resource is functional in the cluster.
Temporarly fix by removing`--cloud-provider=external` option from configuration, or untaint the node with bash comand:
```bash
export MY_NODE=$(sudo kubebuilder/bin/kubectl get nodes -oname | cut -d / -f 2)
sudo kubebuilder/bin/kubectl taint nodes $MY_NODE node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule-
```
