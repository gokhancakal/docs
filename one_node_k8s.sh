export kubeletEx="ExecStart=/usr/bin/kubelet"
export kubeletNw="ExecStart=/usr/bin/kubelet --cgroup-driver=systemd --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"

export dockerEx="ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock"
export dockerNw="ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --exec-opt native.cgroupdriver=systemd"


###################################################################################################
echo -e "\e[1;31m K8s Installation Started! \e[0m" # +Worker+
###################################################################################################
sudo yum-config-manager     --add-repo     https://download.docker.com/linux/centos/docker-ce.repo

sudo tee /etc/yum.repos.d/kubernetes.repo<<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

echo 'net.bridge.bridge-nf-call-iptables=1' | sudo tee -a /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
modprobe br_netfilter

yum install -y kubeadm-1.23.4-0 kubelet-1.23.4-0 kubectl-1.23.4-0 docker-ce-19.03.0 docker-19.03.0

systemctl enable docker
systemctl enable kubelet

sed -i "s#$kubeletEx#$kubeletNw#g" /usr/lib/systemd/system/kubelet.service
sed -i "s#$dockerEx#$dockerNw#g" /usr/lib/systemd/system/docker.service

systemctl daemon-reload
systemctl start kubelet
systemctl start docker

###################################################################################################
#-Worker-
###################################################################################################
sudo kubeadm init

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')&env.IPALLOC_RANGE=10.32.0.0/16" --validate=false
sleep 30

kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml --validate=false
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml --validate=false

kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

mkdir ~/k8s
cd ~/k8s
touch admin-token
touch metallb-config.yaml
touch k8s-dashboard.yaml

cat <<EOF>> ~/k8s/metallb-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
 namespace: metallb-system
 name: config
data:
 config: |
  address-pools:
  - name: default
    protocol: layer2
    addresses:
    - 10.34.39.5 - 10.34.39.8
EOF

kubectl apply -f metallb-config.yaml --validate=false


kubectl taint nodes --all node-role.kubernetes.io/master-

sleep 15

wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/cloud/deploy.yaml
sed -i '266i\    metallb.universe.tf/address-pool: default\' deploy.yaml
kubectl apply -f deploy.yaml --validate=false

kubectl get pods --namespace=ingress-nginx

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
  
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml --validate=false

sleep 15

cat <<EOF>> ~/k8s/k8s-dashboard.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host:
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF


kubectl apply -f k8s-dashboard.yaml --validate=false

kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep admin-user | awk "{print $1}")

cat <<EOF | kubectl apply --validate=false -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply --validate=false -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}" | tee -a admin-token

kubectl get svc -A
kubectl get pod -A

echo -e "\e[1;31m K8s DONE! \e[0m"
