#!/bin/bash

# Exit on error
set -e

MASTER_IP="192.168.122.57"

echo "Joining existing cluster..."

# Function to check if a process is running
is_running() {
    pgrep -f "$1" >/dev/null
}

# Function to check if all components are running
check_running() {
    is_running "kubelet" && \
    is_running "containerd"
}

# Function to kill process if running
stop_process() {
    if is_running "$1"; then
        echo "Stopping $1..."
        sudo pkill -f "$1" || true
        while is_running "$1"; do
            sleep 1
        done
    fi
}

download_components() {
    # Create necessary directories if they don't exist
    sudo mkdir -p ./kubebuilder/bin
    sudo mkdir -p /etc/cni/net.d
    sudo mkdir -p /var/lib/kubelet
    sudo mkdir -p /etc/kubernetes/manifests
    sudo mkdir -p /var/log/kubernetes
    sudo mkdir -p /etc/containerd/
    sudo mkdir -p /run/containerd

    # Download kubebuilder tools if not present
    if [ ! -f "kubebuilder/bin/etcd" ]; then
        echo "Downloading kubebuilder tools..."
        curl -L https://storage.googleapis.com/kubebuilder-tools/kubebuilder-tools-1.30.0-linux-amd64.tar.gz -o /tmp/kubebuilder-tools.tar.gz
        sudo tar -C ./kubebuilder --strip-components=1 -zxf /tmp/kubebuilder-tools.tar.gz
        rm /tmp/kubebuilder-tools.tar.gz
        sudo chmod -R 755 ./kubebuilder/bin
    fi

    if [ ! -f "kubebuilder/bin/kubelet" ]; then
        echo "Downloading kubelet..."
        sudo curl -L "https://dl.k8s.io/v1.30.0/bin/linux/amd64/kubelet" -o kubebuilder/bin/kubelet
        sudo chmod 755 kubebuilder/bin/kubelet
    fi

    # Install CNI components if not present
    if [ ! -d "/opt/cni" ]; then
        sudo mkdir -p /opt/cni
        
        echo "Installing containerd..."
        wget https://github.com/containerd/containerd/releases/download/v2.0.5/containerd-static-2.0.5-linux-amd64.tar.gz -O /tmp/containerd.tar.gz
        sudo tar zxf /tmp/containerd.tar.gz -C /opt/cni/
        rm /tmp/containerd.tar.gz

        echo "Installing runc..."
        sudo curl -L "https://github.com/opencontainers/runc/releases/download/v1.2.6/runc.amd64" -o /opt/cni/bin/runc

        echo "Installing CNI plugins..."
        wget https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz -O /tmp/cni-plugins.tgz
        sudo tar zxf /tmp/cni-plugins.tgz -C /opt/cni/bin/
        rm /tmp/cni-plugins.tgz

        # Set permissions for all CNI components
        sudo chmod -R 755 /opt/cni
    fi
}

setup_configs() {
    # Set up kubeconfig if not already configured
    if ! sudo kubebuilder/bin/kubectl config current-context | grep -q "test-context"; then
        sudo kubebuilder/bin/kubectl config set-credentials test-user --token=1234567890
        sudo kubebuilder/bin/kubectl config set-cluster test-env --server=https://$MASTER_IP:6443 --insecure-skip-tls-verify
        sudo kubebuilder/bin/kubectl config set-context test-context --cluster=test-env --user=test-user --namespace=default 
        sudo kubebuilder/bin/kubectl config use-context test-context
    fi

    # Configure CNI
    cat <<EOF | sudo tee /etc/cni/net.d/10-mynet.conf
{
    "cniVersion": "0.3.1",
    "name": "mynet",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/16",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ]
    }
}
EOF

    # Configure containerd
    cat <<EOF | sudo tee /etc/containerd/config.toml
version = 3

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins.'io.containerd.cri.v1.runtime']
  enable_selinux = false
  enable_unprivileged_ports = true
  enable_unprivileged_icmp = true
  device_ownership_from_security_context = false

[plugins.'io.containerd.cri.v1.images']
  snapshotter = "native"
  disable_snapshot_annotations = true

[plugins.'io.containerd.cri.v1.runtime'.cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = false
EOF

    # Ensure containerd data directory exists with correct permissions
    sudo mkdir -p /var/lib/containerd
    sudo chmod 711 /var/lib/containerd

    # Configure kubelet
    cat << EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: true
  webhook:
    enabled: true
  x509:
    clientCAFile: ""
authorization:
  mode: AlwaysAllow
clusterDomain: "cluster.local"
clusterDNS:
  - "10.0.0.10"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
failSwapOn: false
seccompDefault: true
serverTLSBootstrap: false
containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
staticPodPath: "/etc/kubernetes/manifests"
EOF

    # Create required directories with proper permissions
    sudo mkdir -p /var/lib/kubelet/pods
    sudo chmod 750 /var/lib/kubelet/pods
    sudo mkdir -p /var/lib/kubelet/plugins
    sudo chmod 750 /var/lib/kubelet/plugins
    sudo mkdir -p /var/lib/kubelet/plugins_registry
    sudo chmod 750 /var/lib/kubelet/plugins_registry

    # Ensure proper permissions
    sudo chmod 644 /var/lib/kubelet/config.yaml

    # Generate self-signed kubelet serving certificate if not present
    if [ ! -f "/var/lib/kubelet/pki/kubelet.crt" ] || [ ! -f "/var/lib/kubelet/pki/kubelet.key" ]; then
        echo "Generating self-signed kubelet serving certificate..."
        sudo openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout /var/lib/kubelet/pki/kubelet.key \
            -out /var/lib/kubelet/pki/kubelet.crt \
            -days 365 \
            -subj "/CN=$(hostname)"
        sudo chmod 600 /var/lib/kubelet/pki/kubelet.key
        sudo chmod 644 /var/lib/kubelet/pki/kubelet.crt
    fi
}

start() {
    if check_running; then
        echo "Kubernetes components are already running"
        return 0
    fi

    HOST_IP=$(hostname -I | awk '{print $1}')
    
    # Download components if needed
    download_components
    
    # Setup configurations
    setup_configs

    # Start components if not running
    if ! is_running "containerd"; then
        echo "Starting containerd..."
        export PATH=$PATH:/opt/cni/bin:kubebuilder/bin
        sudo PATH=$PATH:/opt/cni/bin:/usr/sbin /opt/cni/bin/containerd -c /etc/containerd/config.toml &
    fi

    # Set up kubelet kubeconfig
    sudo cp /root/.kube/config /var/lib/kubelet/kubeconfig
    export KUBECONFIG=~/.kube/config

    if ! is_running "kubelet"; then
        echo "Starting kubelet..."
        sudo PATH=$PATH:/opt/cni/bin:/usr/sbin kubebuilder/bin/kubelet \
            --kubeconfig=/var/lib/kubelet/kubeconfig \
            --config=/var/lib/kubelet/config.yaml \
            --root-dir=/var/lib/kubelet \
            --cert-dir=/var/lib/kubelet/pki \
            --hostname-override=$(hostname) \
            --pod-infra-container-image=registry.k8s.io/pause:3.10 \
            --node-ip=$HOST_IP \
            --cloud-provider=external \
            --cgroup-driver=cgroupfs \
            --max-pods=40  \
            --v=1 &
    fi

    echo "Waiting for components to be ready..."
    sleep 10

    echo "Verifying setup..."
    sudo kubebuilder/bin/kubectl get nodes
    sudo kubebuilder/bin/kubectl get all -A
    sudo kubebuilder/bin/kubectl get componentstatuses || true
    sudo kubebuilder/bin/kubectl get --raw='/readyz?verbose'
}

stop() {
    echo "Stopping Kubernetes components..."
    stop_process "kubelet"
    stop_process "containerd"
    echo "All components stopped"
}

cleanup() {
    stop
    echo "Cleaning up..."
    sudo rm -rf /var/lib/kubelet/*
    sudo rm -rf /run/containerd/*
    sudo rm -rf /var/lib/containerd/*
    sudo rm /etc/kubernetes/manifests/*yaml
    echo "Cleanup complete"
}

case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Usage: $0 {start|stop|cleanup}"
        exit 1
        ;;
esac 


# cat >/var/lib/kubelet/kubeconfig<<EOF
# apiVersion: v1
# clusters:
# - cluster:
#     insecure-skip-tls-verify: true
#     server: https://127.0.0.1:6443
#   name: test-env
# contexts:
# - context:
#     cluster: test-env
#     namespace: default
#     user: test-user
#   name: test-context
# current-context: test-context
# kind: Config
# preferences: {}
# users:
# - name: test-user
#   user:
#     token: "1234567890"
# EOF

# cat >/var/lib/kubelet/config.yaml<<EOF
# apiVersion: kubelet.config.k8s.io/v1beta1
# kind: KubeletConfiguration
# authentication:
#   anonymous:
#     enabled: true
#   webhook:
#     enabled: true
#   x509:
#     clientCAFile: "/var/lib/kubelet/ca.crt"
# authorization:
#   mode: AlwaysAllow
# clusterDomain: "cluster.local"
# clusterDNS:
#   - "10.0.0.10"
# resolvConf: "/etc/resolv.conf"
# runtimeRequestTimeout: "15m"
# failSwapOn: false
# seccompDefault: true
# serverTLSBootstrap: false
# containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
# # staticPodPath: "/etc/kubernetes/manifests"
# EOF


# cat >/var/lib/kubelet/join-config.yaml<<EOF
# ---
# apiVersion: kubeadm.k8s.io/v1beta4
# caCertPath: /mnt/mastering-k8s/
# discovery:
#   bootstrapToken:
#     apiServerEndpoint: kube-apiserver:6443
#     token: abcdef.0123456789abcdef
#     unsafeSkipCAVerification: true
#   tlsBootstrapToken: abcdef.0123456789abcdef
# kind: JoinConfiguration
# nodeRegistration:
#   criSocket: unix:///var/run/containerd/containerd.sock
#   imagePullPolicy: IfNotPresent
#   imagePullSerial: true
#   name: $(hostname)
#   taints: null
# timeouts:
#   controlPlaneComponentHealthCheck: 4m0s
#   discovery: 5m0s
#   etcdAPICall: 2m0s
#   kubeletHealthCheck: 4m0s
#   kubernetesAPICall: 1m0s
#   tlsBootstrap: 5m0s
#   upgradeManifests: 5m0s
# EOF