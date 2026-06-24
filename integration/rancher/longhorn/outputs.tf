output "longhorn_namespace" {
  description = "Namespace where Longhorn is installed."
  value       = helm_release.longhorn.namespace
}

output "longhorn_version" {
  description = "Installed Longhorn chart version."
  value       = helm_release.longhorn.version
}

output "fio_job" {
  description = "Name of the fio benchmark Job."
  value       = kubernetes_job.fio.metadata[0].name
}
