sudo apt install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install helm

shopt -s expand_aliases
alias k=../kubebuilder/bin/kubectl

# Install fluxcd
helm upgrade --install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator --namespace flux-system --create-namespace
# flux instance
k apply -f FluxInstance.yaml
# envoy gateway
helm install envoy-gateway oci://docker.io/envoyproxy/gateway-helm --version v1.3.2 --namespace envoy-gateway-system --create-namespace
# envoy gateway config
k apply -f gateway.yml 
# flux github token secret
# read -s -GITHUB_TOKEN?"Enter GitHub token: "
# 
k create secret generic github-auth \
  --from-literal=username=git \
  --from-literal=password=${GITHUB_TOKEN} \
  -n flux-system
# flux image registry secret
k create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username=vkhash \
  --docker-password=${GITHUB_TOKEN} \
  -n flux-system
# Install gitops stack
k apply -f gitops.yaml
# secret in demo needs to be created manually
#gitrepo
# flux install
export FLUX_VERSION="2.5.1"
wget --quiet https://fluxcd.io/install.sh -O /tmp/install-flux.sh
chmod 0700 /tmp/install-flux.sh
/tmp/install-flux.sh

. <(flux completion bash)
flux reconcile image repository -n demo kbot
# imageautomation
# imagepolicy
# imageupdateautomation
# image update
# apply gitless
k apply -f gitless.yml 
