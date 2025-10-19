#!/bin/bash

# Exit on error
set -e

HOST_IP=$(hostname -I | awk '{print $1}')
ETCD_VERSION="v3.5.13"
KUBE_API_VERSION="v1.30.0"
KUBE_CONTROL_MANAGER_VERSION=$KUBE_API_VERSION
KUBE_SCHEDULER_VERSION=$KUBE_API_VERSION

echo "generating etcd manifest..."
cat >/etc/kubernetes/manifests/etcd.yaml<<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --advertise-client-urls=http://$HOST_IP:2379
    - --listen-client-urls=http://0.0.0.0:2379
    - --data-dir=/var/lib/etcd
    - --listen-peer-urls=http://0.0.0.0:2380
    - --initial-cluster=default=http://$HOST_IP:2380
    - --initial-advertise-peer-urls=http://$HOST_IP:2380
    - --initial-cluster-state=new
    - --initial-cluster-token=test-token
    image: quay.io/coreos/etcd:$ETCD_VERSION
    imagePullPolicy: IfNotPresent
    name: etcd
    resources:
      requests:
        cpu: 25m
        memory: 100Mi
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
  hostNetwork: true
  priority: 2000001000
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /mnt/mastering-k8s/etcd
      type: DirectoryOrCreate
    name: etcd-data
status: {}
EOF

echo "generating kube-apiserver manifest..."
cat >/etc/kubernetes/manifests/kube-apiserver.yaml<<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --etcd-servers=http://$HOST_IP:2379
    - --service-cluster-ip-range=10.0.0.0/24
    - --bind-address=0.0.0.0
    - --secure-port=6443
    - --advertise-address=$HOST_IP
    - --authorization-mode=AlwaysAllow
    - --token-auth-file=/tmp/mastering-k8s/token.csv
    - --enable-priority-and-fairness=false
    - --allow-privileged=true
    - --profiling=false
    - --storage-backend=etcd3
    - --storage-media-type=application/json
    - --v=0
    - --cloud-provider=external
    - --service-account-issuer=https://kubernetes.default.svc.cluster.local
    - --service-account-key-file=/tmp/mastering-k8s/sa.pub
    - --service-account-signing-key-file=/tmp/mastering-k8s/sa.key
    image: registry.k8s.io/kube-apiserver:$KUBE_API_VERSION
    imagePullPolicy: IfNotPresent
    name: kube-apiserver
    resources:
      requests:
        cpu: 50m
    volumeMounts:
    - mountPath: /tmp/mastering-k8s
      name: tmp-mastering-k8s
      readOnly: true
  hostNetwork: true
  priority: 2000001000
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /tmp/mastering-k8s
      type: DirectoryOrCreate
    name: tmp-mastering-k8s
status: {}
EOF

echo "generating kube-controller-manager manifest..."
cat >/etc/kubernetes/manifests/kube-controller-manager.yaml<<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-controller-manager
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --leader-elect=false
    - --cloud-provider=external
    - --service-cluster-ip-range=10.0.0.0/24
    - --cluster-name=kubernetes
    - --root-ca-file=/etc/kubernetes/pki/ca.crt
    - --service-account-private-key-file=/tmp/mastering-k8s/sa.key
    - --use-service-account-credentials=true
    - --v=2
    image: registry.k8s.io/kube-controller-manager:$KUBE_CONTROL_MANAGER_VERSION
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10257
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: kube-controller-manager
    resources:
      requests:
        cpu: 25m
    startupProbe:
      failureThreshold: 24
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10257
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /etc/kubernetes/controller-manager.conf
      name: kubeconfig
      readOnly: true
    - mountPath: /etc/kubernetes/pki/ca.crt
      name: kubelet-ca
      readOnly: true
    - mountPath: /tmp/mastering-k8s
      name: tmp-mastering-k8s
      readOnly: true
  hostNetwork: true
  priority: 2000001000
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /root/.kube/config
      type: FileOrCreate
    name: kubeconfig
  - hostPath:
      path: /tmp/mastering-k8s
      type: DirectoryOrCreate
    name: tmp-mastering-k8s
  - hostPath:
      path: /var/lib/kubelet/ca.crt
      type: FileOrCreate
    name: kubelet-ca
status: {}
EOF

echo "generating kube-scheduler manifest..."
cat >/etc/kubernetes/manifests/kube-scheduler.yaml<<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-scheduler
    - --kubeconfig=/etc/kubernetes/scheduler.conf
    - --leader-elect=false
    - --v=2
    - --bind-address=0.0.0.0
    image: registry.k8s.io/kube-scheduler:$KUBE_SCHEDULER_VERSION
    imagePullPolicy: IfNotPresent
    name: kube-scheduler
    resources:
      requests:
        cpu: 25m
    volumeMounts:
    - mountPath: /etc/kubernetes/scheduler.conf
      name: kubeconfig
      readOnly: true
  hostNetwork: true
  priority: 2000001000
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /root/.kube/config
      type: FileOrCreate
    name: kubeconfig
status: {}
EOF
