
output "kubernetes_etcd_public_ip" {
  value = "${join(",", aws_instance.etcd.*.public_ip)}"
}

output "kubernetes_etcd_private_ip" {
  value = "${join(",", aws_instance.etcd.*.private_ip)}"
}

output "kubernetes_etcd_private_dns" {
  value = "${aws_instance.etcd.*.private_dns}"
}
