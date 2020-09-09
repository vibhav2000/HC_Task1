provider "aws" {
  access_key = "AKIAVPWYEA7BKITTQASJ"
  secret_key = "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"
  region     = "ap-south-1"
  profile    = "vibhav1"
}

resource "aws_key_pair" "tfkey" {


key_name  = "tfkey"
public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAo5lBBX6GEO6l3B9NR+usDOfI43mvYanQtED11t+09255hci7+C21JnubHQ8LNqy08D15/9ycQTKNG+sXdUz/m5SZD+38Nnxd2OaIKREqly6z1oOuN12wPtPTHiD3kO43UsPoSBdvmR/2Cvc1JT3eh/r9t10pv7EIdCOS4y8YHU3ZMrTiY/u6sGYWsSnqVoHTIfO8xQ+857Mbs0Z+f2S8jsPBTEU9BEGt2fVsRb6rOYY23rix5jT3EmX1Ap3N4bGtC4bw7jtyJebWBPgdkzumV44pmu6fXPbTX2KI+3Mnl6fRaV7bEtSUlKv2Yi/3gSn5htItGe3LrVnWbpGntHik5Q== rsa-key-20200828"

}


resource "aws_security_group" "allow_ssh_http" {

  name        = "allow_ssh_http"
  description = "Allow http inbound traffic"
  vpc_id      = "vpc-1bf3ee73"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_ssh"
  }
}


resource "aws_ebs_volume" "ebs_vol1" {
  depends_on = [
    aws_security_group.allow_ssh_http,
  ]
  availability_zone = "ap-south-1a"
  size              = 1
  
  tags = {
    Name = "ebs-vol1"
  }
}


resource "aws_instance" "inst1" {
  depends_on = [
    aws_ebs_volume.ebs_vol1,
  ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "tfkey"
  security_groups = ["allow_ssh_http"]
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("D:/Cloud/tfkey.pem")
    host     = aws_instance.inst1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install git -y",
      "sudo yum install httpd -y",
      "sudo service httpd start",
    ]
  }
  tags = {
    Name = "inst1"
  }
}
resource "aws_volume_attachment" "ebs_att" {
  depends_on = [
    aws_ebs_volume.ebs_vol1,aws_instance.inst1,
  ]
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.ebs_vol1.id
  instance_id = aws_instance.inst1.id
  force_detach = true
}

resource "null_resource" "public_ip" {
     depends_on = [
    aws_instance.inst1,
  ]
	provisioner "local-exec" {
		command = "echo ${aws_instance.inst1.public_ip} > publicip.txt"
	}
}

resource "null_resource" "ebs_mount"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("D:/Cloud/tfkey.pem")
    host     = aws_instance.inst1.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdf",
      "sudo mount  /dev/xvdf  /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/vibhav2000/HC_Task1.git /var/www/html/"
    ]
  }
}


resource "aws_s3_bucket" "tf_bucket" {
  depends_on = [
    aws_instance.inst1,
  ]
  bucket = "tfbucket112"
  acl = "public-read"

  tags = {
    Name        = "tfbucket112"
    Environment = "Dev"
  }
}
resource "null_resource" "git_base"  {

  depends_on = [
    aws_s3_bucket.tf_bucket,
  ]
   provisioner "local-exec" {
    working_dir="F:/Takss_LW/HybridMultiCloud/task1/"
    command ="mkdir task1-git"
  }
  provisioner "local-exec" {
    working_dir="F:/Takss_LW/HybridMultiCloud/task1/"
    command ="git clone https://github.com/vibhav2000/HC_Task1.git  F:/Takss_LW/HybridMultiCloud/task1/task1-git"
  }
   
}

resource "aws_ebs_snapshot" "Webserver_snapshot" {
  volume_id = aws_ebs_volume.ebs_vol1.id

  tags = {
    Name = "WebServer"
  }
  depends_on =[
    aws_instance.inst1
  ]
}


resource "aws_s3_bucket_object" "s3_upload" {
  depends_on = [
    null_resource.git_base,
  ]
  for_each = fileset("F:/Takss_LW/HybridMultiCloud/task1/", "*.jpg")

  bucket = "tfbucket112"
  key    = each.value
  source = "F:/Takss_LW/HybridMultiCloud/task1/${each.value}"
  etag   = filemd5("F:/Takss_LW/HybridMultiCloud/task1/${each.value}")
  acl = "public-read"

}


locals {
  s3_origin_id = "s3-${aws_s3_bucket.tf_bucket.id}"
}

resource "aws_cloudfront_distribution" "s3_cloud" {
  depends_on = [
    aws_s3_bucket_object.s3_upload,
  ]
  origin {
    domain_name = aws_s3_bucket.tf_bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "TF connecting s3 to the cloudfront"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "null_resource" "updating_code"  {

  depends_on = [
    aws_cloudfront_distribution.s3_cloud,
  ]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("D:/Cloud/tfkey.pem")
    host = aws_instance.inst1.public_ip
	}
  for_each = fileset("F:/Takss_LW/HybridMultiCloud/task1/", "*.jpg")
  provisioner "remote-exec" {
    inline = [
	"sudo su << EOF",
	"echo \"<p>Here is a picture of The Moon.</p>\" >> /var/www/html/index.html",
	"echo \"<img src='http://${aws_cloudfront_distribution.s3_cloud.domain_name}/${each.value}' width='50%' height='50%'>\" >> /var/www/html/index.html",
        "EOF"
			]
	}
	 provisioner "local-exec" {
		command = "start chrome  ${aws_instance.inst1.public_ip}/index.html"
	}

}