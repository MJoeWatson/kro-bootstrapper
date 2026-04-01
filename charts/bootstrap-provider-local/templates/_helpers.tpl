{{- define "bootstrap-provider-local.fullname" -}}
{{- default .Chart.Name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bootstrap-provider-local.esoTokenSecretName" -}}
{{- "eso-token" -}}
{{- end -}}
