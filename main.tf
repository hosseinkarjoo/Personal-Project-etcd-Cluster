terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.17"
    }
  }
}

##########PREPRATION############
provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

resource "aws_key_pair" "my-key" {
  key_name = "My_Key"
  public_key = file("/root/.ssh/id_rsa.pub")
}

data "aws_ami" "latest-ec2" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

##########NETWORKING########

resource "aws_vpc" "k8s-vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "k8s-subnet" {
  vpc_id = "${aws_vpc.k8s-vpc.id}"
  cidr_block = "10.0.1.0/24"
#  availability_zone = var.region
}


resource "aws_internet_gateway" "k8s-gw" {
  vpc_id = "${aws_vpc.k8s-vpc.id}"
}

resource "aws_route_table" "k8s-rtable" {
    vpc_id = "${aws_vpc.k8s-vpc.id}"
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.k8s-gw.id}"
    }
}

resource "aws_route_table_association" "k8s-rtable-as" {
  subnet_id = "${aws_subnet.k8s-subnet.id}"
  route_table_id = "${aws_route_table.k8s-rtable.id}"
}


####CREATING EC2 INSTANCES / etcd##########
resource "aws_instance" "etcd" {
  count = 3
  ami = data.aws_ami.latest-ec2.id
  instance_type = "t2.medium"
  key_name = aws_key_pair.my-key.key_name
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.k8s-sg.id}"]
  subnet_id = aws_subnet.k8s-subnet.id
  tags = {
    NAME = "ETCD-${count.index}"
  }
}


resource "aws_security_group" "k8s-sg" {
  vpc_id = "${aws_vpc.k8s-vpc.id}"
  name = "k8s-sg"

  ingress {
    cidr_blocks = [ "0.0.0.0/0" ]
    protocol = "tcp"
    from_port = 22
    to_port = 22
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port = 8
    to_port = 0
    protocol = "icmp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

}

#############GENERATE CERTIFICATE##########################

#data "template_file" "certificates" {
#    template = "${file("./kubernetes-csr.json")}"
#    depends_on = [aws_instance.etcd]
#    vars = {

#      etcd0_ip = "${aws_instance.etcd.0.private_ip}"
#      etcd1_ip = "${aws_instance.etcd.1.private_ip}"
#      etcd2_ip = "${aws_instance.etcd.2.private_ip}"
#
#      etcd0_dns = "${aws_instance.etcd.0.private_dns}"
#      etcd1_dns = "${aws_instance.etcd.1.private_dns}"
#      etcd2_dns = "${aws_instance.etcd.2.private_dns}"
#    }
#}
#resource "null_resource" "certificates" {
#  triggers = {
#    template_rendered = "${ data.template_file.certificates.rendered }"
#  }
#  provisioner "local-exec" {
#    command = "echo '${ data.template_file.certificates.rendered }' > ./cert/kubernetes-csr.json"
#  }
#  provisioner "local-exec" {
#    command = " cfssl gencert -initca ca-csr.json | cfssljson -bare ca; cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes ./cert/kubernetes-csr.json | cfssljson -bare kubernetes"
#  }
#}

data "template_file" "inventory" {
  template = "${file("./templates/inventory.ini")}"
  vars = {
    etcd-1-pub = "${aws_instance.etcd.0.public_ip}"
    etcd-2-pub = "${aws_instance.etcd.1.public_ip}"
    etcd-3-pub = "${aws_instance.etcd.2.public_ip}"

    etcd-1-prv = "${aws_instance.etcd.0.private_ip}"
    etcd-2-prv = "${aws_instance.etcd.1.private_ip}"
    etcd-3-prv = "${aws_instance.etcd.2.private_ip}"

    etcd-1-name = "${aws_instance.etcd.0.private_dns}"
    etcd-2-name = "${aws_instance.etcd.1.private_dns}"
    etcd-3-name = "${aws_instance.etcd.2.private_dns}"

  }
}
resource "null_resource" "inventory" {
  depends_on = [aws_instance.etcd[0], aws_instance.etcd[1], aws_instance.etcd[2]]
  triggers = {
    template_rendered = "${data.template_file.inventory.rendered}"
  }
  provisioner "local-exec" {
    command = "echo '${data.template_file.inventory.rendered}' > ./inventory.ini"
 }
}


data "template_file" "openssl-csr" {
  template = "${file("./artifacts/csr.conf.template")}"
  vars = {
    etcd-1-pub = "${aws_instance.etcd.0.public_ip}"
    etcd-2-pub = "${aws_instance.etcd.1.public_ip}"
    etcd-3-pub = "${aws_instance.etcd.2.public_ip}"

    etcd-1-prv = "${aws_instance.etcd.0.private_ip}"
    etcd-2-prv = "${aws_instance.etcd.1.private_ip}"
    etcd-3-prv = "${aws_instance.etcd.2.private_ip}"

    etcd-1-name = "${aws_instance.etcd.0.private_dns}"
    etcd-2-name = "${aws_instance.etcd.1.private_dns}"
    etcd-3-name = "${aws_instance.etcd.2.private_dns}"

  }
}
resource "null_resource" "openssl-csr" {
  triggers = {
    template_rendered = "${data.template_file.openssl-csr.rendered}"
  }
  provisioner "local-exec" {
    command = "echo '${data.template_file.openssl-csr.rendered}' > ./artifacts/csr.conf"
 }
}
