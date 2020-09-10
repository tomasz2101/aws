output "aws_k8s_cmd" {
    value = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_id}"
}
