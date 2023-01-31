data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "opal_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    # not for prod - any authenticated user or role in the account can assume admin role for this cluster
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

#admin
resource "aws_iam_role" "eks_cluster_admin" {
  name                 = "OpalEKSClusterAdmin"
  assume_role_policy   = data.aws_iam_policy_document.opal_assume_role_policy.json
  max_session_duration = 1 * 60 * 60
}
resource "aws_iam_policy" "eks_cluster_admin" {
  name   = "OpalEKSClusterAdminAccess"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "List",
      "Effect": "Allow",
      "Action": [
        "eks:ListClusters",
        "eks:DescribeAddonVersions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Write",
      "Effect": "Allow",
      "Action": "eks:*",
      "Resource": [
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${module.eks.cluster_name}/*/*",
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:addon/${module.eks.cluster_name}/*/*",
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:identityproviderconfig/${module.eks.cluster_name}/*/*/*",
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}",
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:nodegroup/${module.eks.cluster_name}/*/*"
      ]
    }
  ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "eks_cluster_admin_cluster" {
  policy_arn = aws_iam_policy.eks_cluster_admin.arn
  role       = aws_iam_role.eks_cluster_admin.name
}
