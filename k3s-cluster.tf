resource "null_resource" "k3s_master" {
  depends_on = [null_resource.k3s_master_vm, null_resource.bimser_builder]
  
  connection {
    type        = "ssh"
    user        = var.vm_user

    host        = regex("master_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | sh -s - server --node-external-ip ${regex("master_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]} --flannel-iface=enp0s1 --disable traefik",
      "sleep 15",
      
      "sudo kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml",
      
      "sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/token",
      "sudo chmod 644 /tmp/token",
      "sudo chmod 644 /etc/rancher/k3s/k3s.yaml"
    ]
  }
}

resource "null_resource" "download_token" {
  depends_on = [null_resource.k3s_master]

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no ${var.vm_user}@${regex("master_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]}:/tmp/token ./node_token.txt"
  }
}

resource "null_resource" "k3s_worker" {
  depends_on = [null_resource.download_token, null_resource.k3s_worker_vm]

  connection {
    type        = "ssh"
    user        = var.vm_user
    host        = regex("worker_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "file" {
    source      = "./node_token.txt"
    destination = "/tmp/node_token.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "TOKEN=$(cat /tmp/node_token.txt)",
      "curl -sfL https://get.k3s.io | K3S_URL=https://${regex("master_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]}:6443 K3S_TOKEN=$TOKEN sh -s - --flannel-iface=enp0s1"
    ]
  }
}

resource "null_resource" "setup_builder_kubeconfig" {

  depends_on = [null_resource.k3s_worker, null_resource.k3s_master]

  provisioner "local-exec" {
    command = <<-EOT
      MASTER_IP=$(grep "master_ip=" nodes_ip.txt | cut -d'=' -f2)
      BUILDER_IP=$(grep "builder_ip=" nodes_ip.txt | cut -d'=' -f2)

      echo "Master: $MASTER_IP , Builder: $BUILDER_IP"

      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" > k3s_builder.yaml

      sed -i '' "s/127.0.0.1/$MASTER_IP/g" k3s_builder.yaml

      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$BUILDER_IP "mkdir -p /home/${var.vm_user}/.kube"
      scp -o StrictHostKeyChecking=no k3s_builder.yaml ${var.vm_user}@$BUILDER_IP:/home/${var.vm_user}/.kube/config

      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$BUILDER_IP "chmod 600 /home/${var.vm_user}/.kube/config"

      rm k3s_builder.yaml
    EOT
  }
}

# resource "null_resource" "install_metallb" {
#   depends_on = [null_resource.k3s_master, null_resource.k3s_worker, null_resource.configure_k3s_registry]

#   connection {
#     type        = "ssh"
#     user        = var.vm_user
#     host        = regex("master_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]
#     private_key = file(var.ssh_private_key_path)
#   }

#   provisioner "file" {
#     source      = "manifests/metallb-config.yaml"
#     destination = "/tmp/metallb-config.yaml"
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "sudo chmod 644 /etc/rancher/k3s/k3s.yaml",
#       "sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml",
      
#       "echo 'MetalLB podlari bekleniyor...'",
#       "sudo kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s",
      
#       "sleep 20",

#       "echo 'MetalLB IP havuzu yapılandırılıyor...'",
#       "for i in 1 2 3 4 5; do sudo kubectl apply -f /tmp/metallb-config.yaml && break || (echo 'Bekleniyor...' && sleep 10); done",

#       "echo 'Ingress servisi LoadBalancer yapiliyor...'",
#       "sudo kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'"
#     ]
#   }
# }

resource "null_resource" "create_ssl_secret" {
  depends_on = [null_resource.setup_builder_kubeconfig]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.vm_user
      host        = regex("builder_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]
      private_key = file(var.ssh_private_key_path)
    }

    inline = [
      "openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj '/CN=app.local'",
      "kubectl create secret tls app-tls-secret --key /tmp/tls.key --cert /tmp/tls.crt --dry-run=client -o yaml | kubectl apply -f -"
    ]
  }
}

resource "null_resource" "setup_builder_registry" {
  depends_on = [null_resource.bimser_builder, null_resource.setup_builder_kubeconfig]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.vm_user
      host        = regex("builder_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]
      private_key = file(var.ssh_private_key_path)
    }

    inline = [
      "docker run -d -p 5001:5000 --restart=always --name registry registry:2 || true",

      "BUILDER_IP=$(hostname -I | awk '{print $1}')",

      "echo \"{\\\"insecure-registries\\\": [\\\"$BUILDER_IP:5001\\\"]}\" | sudo tee /etc/docker/daemon.json",

      "sudo systemctl restart docker"
    ]
  }
}


resource "null_resource" "configure_k3s_registry" {
  depends_on = [null_resource.k3s_master, null_resource.k3s_worker, null_resource.setup_builder_registry]

  provisioner "local-exec" {
    command = <<-EOT
      BUILDER_IP=$(grep "builder_ip=" nodes_ip.txt | cut -d'=' -f2)
      MASTER_IP=$(grep "master_ip=" nodes_ip.txt | cut -d'=' -f2)
      WORKER_IP=$(grep "worker_ip=" nodes_ip.txt | cut -d'=' -f2)

      cat <<EOF > registries.yaml
      mirrors:
        "$BUILDER_IP:5001":
          endpoint:
            - "http://$BUILDER_IP:5001"
      EOF

      scp -o StrictHostKeyChecking=no registries.yaml ${var.vm_user}@$MASTER_IP:/tmp/registries.yaml
      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$MASTER_IP "sudo mkdir -p /etc/rancher/k3s && sudo mv /tmp/registries.yaml /etc/rancher/k3s/registries.yaml && sudo systemctl restart k3s"

      scp -o StrictHostKeyChecking=no registries.yaml ${var.vm_user}@$WORKER_IP:/tmp/registries.yaml
      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$WORKER_IP "sudo mkdir -p /etc/rancher/k3s && sudo mv /tmp/registries.yaml /etc/rancher/k3s/registries.yaml && sudo systemctl restart k3s-agent"

      rm registries.yaml
    EOT
  }
}


resource "null_resource" "sync_app_files" {
  depends_on = [null_resource.setup_builder_kubeconfig, null_resource.setup_builder_registry, null_resource.configure_k3s_registry]

  provisioner "local-exec" {
    command = <<-EOT
      BUILDER_IP=$(grep "builder_ip=" nodes_ip.txt | cut -d'=' -f2) 
      
      IMAGE_TAG="v-$(date +%Y%m%d-%H%M)"
      IMAGE_NAME="bimser-python-app"
      FULL_IMAGE_PATH="$BUILDER_IP:5001/$IMAGE_NAME:$IMAGE_TAG"

      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$BUILDER_IP "mkdir -p /home/${var.vm_user}/bimser-app/manifests" 
      scp -o StrictHostKeyChecking=no app.py Dockerfile ${var.vm_user}@$BUILDER_IP:/home/${var.vm_user}/bimser-app/ 
      scp -o StrictHostKeyChecking=no manifests/*.yaml ${var.vm_user}@$BUILDER_IP:/home/${var.vm_user}/bimser-app/manifests/
      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$BUILDER_IP "sed -i \"s|image:.*|image: $FULL_IMAGE_PATH|g\" /home/${var.vm_user}/bimser-app/manifests/deployment.yaml"
      ssh -o StrictHostKeyChecking=no ${var.vm_user}@$BUILDER_IP <<EOF
        cd /home/${var.vm_user}/bimser-app
        kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
        kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s
        sleep 15
        docker build -t $FULL_IMAGE_PATH .
        docker push $FULL_IMAGE_PATH
        kubectl apply -f manifests/
        kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec": {"type": "LoadBalancer"}}'
EOF
    EOT 
  }
}