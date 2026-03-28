{{- define "argocd-bootstrap.fullname" -}}
{{- default .Chart.Name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "argocd-bootstrap.sentinelExists" -}}
{{- if (lookup "v1" "ConfigMap" .Values.bootstrap.sentinel.namespace .Values.bootstrap.sentinel.name) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "argocd-bootstrap.shouldBootstrap" -}}
{{- if eq (include "argocd-bootstrap.sentinelExists" . | trim) "true" -}}
false
{{- else -}}
true
{{- end -}}
{{- end -}}
