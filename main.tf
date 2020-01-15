# Specify the provider and access details
  provider "aws" {
  region = var.region
}

###################### Security Groups Part ######################
resource "aws_security_group" "elb" {
    name        = "sg_splunk_elb"
    description = "Used in the terraform"
    vpc_id      = var.vpc_id
    # HTTP access from anywhere
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    # HTTPS access from anywhere
    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    # outbound internet access
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "all" {
    name        = "sg_splunk_all"
    description = "Common rules for all"
    vpc_id      = var.vpc_id
    # Allow SSH admin access
    ingress {
        from_port   = "22"
        to_port     = "22"
        protocol    = "tcp"
        cidr_blocks = [var.admin_cidr_block]
    }
    # Allow Web admin access
    ingress {
        from_port   = var.httpport
        to_port     = var.httpport
        protocol    = "tcp"
        cidr_blocks = [var.admin_cidr_block]
    }
    # full outbound  access
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group_rule" "interco" {
    # Allow all ports between splunk servers
    type                        = "ingress"
    from_port                   = "0"
    to_port                     = "0"
    protocol                    = "-1"
    security_group_id           = aws_security_group.all.id
    source_security_group_id    = aws_security_group.all.id
}

resource "aws_security_group" "searchhead" {
    name             = "sg_splunk_searchhead"
    description      = "Used in the  terraform"
    vpc_id           = var.vpc_id
    #HTTP  access  from  the  ELB
    ingress {
        from_port        = var.httpport
        to_port          = var.httpport
        protocol         = "tcp"
        security_groups  = [aws_security_group.elb.id]
    }
}


###################### Instances part ######################
resource "aws_instance" "master" {
    connection {
        user = var.instance_user
    }
    tags = {
        Name = "CM"
    }
    ami                         = var.ami
    instance_type               = var.instance_type_indexer
    key_name                    = var.key_name
    subnet_id                   = element(split(",", var.subnets), "0")
    vpc_security_group_ids      = [aws_security_group.all.id]
}

resource "aws_instance" "deploymentserver" {
    connection {
        user = var.instance_user
    }
    tags = {
        Name = "DS"
    }
    ami                         = var.ami
    instance_type               = var.instance_type_indexer
    key_name                    = var.key_name
    #private_ip                  = var.deploymentserver_ip
    subnet_id                   = element(split(",", var.subnets), "0")
    vpc_security_group_ids      = [aws_security_group.all.id]
}

resource "aws_instance" "indexer" {
    count                       = var.count_indexer
    connection {
        user = var.instance_user
    }
    tags = {
        Name = "IDX"
    }
    ami                         = var.ami
    instance_type               = var.instance_type_indexer
    key_name                    = var.key_name
    subnet_id                   = element(split(",", var.subnets), count.index)
    vpc_security_group_ids      = [aws_security_group.all.id]
}
###################### searchhead autoscaling part ######################
resource "aws_launch_configuration" "searchhead" {
    name = "lc_splunk_searchhead"
    connection {
        user = var.instance_user
    }
    image_id                    = var.ami
    instance_type               = var.instance_type_searchhead
    key_name                    = var.key_name
    security_groups             = [aws_security_group.all.id, aws_security_group.searchhead.id]
}

resource "aws_autoscaling_group" "searchhead" {
    name = "asg_splunk_searchhead"
    availability_zones         = split(",", var.availability_zones)
    vpc_zone_identifier        = split(",", var.subnets)
    min_size                   = var.asg_searchhead_min
    max_size                   = var.asg_searchhead_max
    desired_capacity           = var.asg_searchhead_desired
    health_check_grace_period  = 300
    health_check_type          = "EC2"
    launch_configuration       = aws_launch_configuration.searchhead.name
    tag {
        key                 = "Name"
        value               = "SH"
        propagate_at_launch = true
    }
}
