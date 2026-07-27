data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "k3s_node" {
  name               = "${var.project_name}-k3s-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Lets nodes `docker/crictl pull` images from the ECR repos below.
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "k3s_node" {
  name = "${var.project_name}-k3s-node"
  role = aws_iam_role.k3s_node.name
}
