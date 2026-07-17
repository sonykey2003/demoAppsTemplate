{{- define "sensitiveData" -}}
{{- $data := get . "data" | trim -}}
{{- if $data -}}
{{- $data | b64enc -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}
