variable "ssh_public_key_path" {
  description = "Multipass makinelerine eklenecek SSH public key yolu"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Makinelere bağlanmak için kullanılacak SSH private key yolu"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "vm_user" {
  description = "Makinelerin varsayılan kullanıcı adı"
  type        = string
  default     = "ubuntu"
}

variable "builder_specs" {
  description = "Builder makinesi özellikleri"
  type        = map(string)
  default = {
    cpus   = "2"
    memory = "2G"
    disk   = "10G"
  }
}

variable "cluster_specs" {
  description = "Master ve Worker node özellikleri"
  type        = map(string)
  default = {
    cpus   = "1"
    memory = "1G"
    disk   = "5G"
  }
}