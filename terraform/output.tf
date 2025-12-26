
data "local_file" "nodes_ips" {
  depends_on = [null_resource.k3s_worker_vm]
  filename   = "nodes_ip.txt"
}

output "ssh_connect_bimser_builder" {
  value       = "ssh ubuntu@${regex("builder_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]}"
  description = "Bimser Builder (Yönetim) makinesine bağlanma komutu."
}

output "ssh_connect_master" {
  value       = "ssh ubuntu@${regex("master_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]}"
  description = "K3s Master node'una bağlanma komutu."
}

output "ssh_connect_worker" {
  value       = "ssh ubuntu@${regex("worker_ip=([0-9.]+)", data.local_file.nodes_ips.content)[0]}"
  description = "K3s Worker node'una bağlanma komutu."
}