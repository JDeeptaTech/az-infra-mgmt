variable "vsphere_user" {}
variable "vsphere_password" {}
variable "vsphere_server" {}

variable "datacenter" {}
variable "cluster" {}
variable "datastore" {}
variable "template" {}
variable "vm_name" {}
variable "network" {}

variable "static_ip" {}
variable "gateway" {}
variable "netmask" {}
variable "dns_servers" {
  type = list(string)
}
