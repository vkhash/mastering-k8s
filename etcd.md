## This script installs etcdctl and etcdutl, tools for interacting with etcd.
```bash
ETCD_VER=v3.6.1
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=https://storage.googleapis.com/etcd
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar --extract --verbose \
    --file=/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz \
    --directory=kubebuilder/bin \
    --strip-components=1 \
    --no-same-owner \
        etcd-v3.6.1-linux-amd64/etcdctl etcd-v3.6.1-linux-amd64/etcdutl
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
kubebuilder/bin/etcdutl version
kubebuilder/bin/etcdctl version
```
## This script installs kubectl, the command-line tool for interacting with Kubernetes clusters.
```bash
cat /proc/$(pgrep kube-apiserver)/net/tcp|grep 094B 
```
## This script installs ctr, the containerd client.
```bash
sudo ctr -n k8s.io c ls
sudo ctr -n k8s.io c info <>
sudo ctr -n k8s.io t kill 
sudo ctr -n k8s.io t
sudo ctr -n k8s.io t ls
```
# This script lists the cgroup directories for the kubepods.
```bash
sudo ls /sys/fs/cgroup/kubepods/besteffort/
```
# This script lists the cgroup directories for the kubepods with the systemd hierarchy.
```bash
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 get /registry/pods --prefix --keys-only
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 get /registry/pods/default/test-pod -w json| jq -r '.kvs[0].value'|base64 -d|jq
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 etcdctl endpoint status --write-out=table
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 endpoint status --write-out=table
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 defrag
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 endpoint status --write-out=table
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 snapshot save /tmp/etcd-backup.db
```
```bash
ll /tmp/etcd-backup.db
kubebuilder/bin/etcdutl snapshot status /tmp/etcd-backup.db
kubebuilder/bin/etcdctl --endpoints 127.0.0.1:2379 etcdctl endpoint status --write-out=table
```
