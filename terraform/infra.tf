resource "null_resource" "bimser_builder" {
  provisioner "local-exec" {
    command = <<-EOT

      multipass delete bimser-builder --purge || true

      multipass launch --name bimser-builder --cpus ${var.builder_specs.cpus} --memory ${var.builder_specs.memory} --disk ${var.builder_specs.disk} > /dev/null 2>&1
      
      echo "Makinenin 'Running' olması bekleniyor..."
      until multipass info bimser-builder | grep -q "Running"; do sleep 2; done

      echo "Bimser Builder makinesi hazirlaniyor..."
      sleep 20 
      
      IP=$(multipass info bimser-builder --format csv | grep bimser-builder | cut -d, -f3)
      echo "builder_ip=$IP" > nodes_ip.txt
      
      echo "SSH servisinin hazir olmasi bekleniyor..."
      until nc -zvw1 $IP 22; do sleep 2; done

      echo "Builder uzerine SSH yetkilendirme yapiliyor..."
      # 3. SSH Yetkilendirme
      multipass exec bimser-builder -- bash -c "mkdir -p ~/.ssh && echo '${file(var.ssh_public_key_path)}' >> ~/.ssh/authorized_keys"


      echo "Builder uzerine Docker ve Toollar kuruluyor..."
      ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 ${var.vm_user}@$IP <<EOF
        sudo apt-get update
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker ${var.vm_user}
        ARCH=\$(dpkg --print-architecture)
        curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/\$ARCH/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
EOF
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete bimser-builder --purge && rm -f nodes_ip.txt"
  }
}


resource "null_resource" "k3s_master_vm" {
  depends_on = [null_resource.bimser_builder]
  
  provisioner "local-exec" {
    command = <<-EOT
      multipass delete master --purge || true
      echo "Master VM hazirlaniyor..."
      multipass launch --name master --cpus ${var.cluster_specs.cpus} --memory ${var.cluster_specs.memory} --disk ${var.cluster_specs.disk} > /dev/null 2>&1
      
      IP=$(multipass info master --format csv | grep master | cut -d, -f3)
      echo "master_ip=$IP" >> nodes_ip.txt
      
      multipass exec master -- bash -c "mkdir -p ~/.ssh && echo '${file(var.ssh_public_key_path)}' >> ~/.ssh/authorized_keys"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete master --purge"
  }
}

resource "null_resource" "k3s_worker_vm" {
  depends_on = [null_resource.k3s_master_vm]
  
  provisioner "local-exec" {
    command = <<-EOT
      multipass delete worker --purge || true
      echo "Worker VM hazirlaniyor..."
      multipass launch --name worker --cpus ${var.cluster_specs.cpus} --memory ${var.cluster_specs.memory} --disk ${var.cluster_specs.disk} > /dev/null 2>&1
      
      IP=$(multipass info worker --format csv | grep worker | cut -d, -f3)
      echo "worker_ip=$IP" >> nodes_ip.txt
      
      multipass exec worker -- bash -c "mkdir -p ~/.ssh && echo '${file(var.ssh_public_key_path)}' >> ~/.ssh/authorized_keys"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete worker --purge"
  }
}