{{- define "grick.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "grick.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "grick.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "grick.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "grick.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grick.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "grick.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "grick.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Resolved evidence storage provider, as the containers receive it and the app
reads it (lib/storage/provider.ts): EVIDENCE_STORAGE_PROVIDER, then
STORAGE_PROVIDER, then s3 when a bucket is set. envFrom loads the ConfigMap
then the Secret, so secretEnv overrides env for the same key, and in the
ConfigMap env overrides storage.provider (see grick.storage.configData).
secretEnv only reaches the pods when the chart renders the Secret.
*/}}
{{- define "grick.storage.provider" -}}
{{- $env := .Values.env | default dict -}}
{{- $secretEnv := dict -}}
{{- if not .Values.existingSecret }}{{ $secretEnv = .Values.secretEnv | default dict }}{{ end -}}
{{- $explicit := coalesce $secretEnv.EVIDENCE_STORAGE_PROVIDER $env.EVIDENCE_STORAGE_PROVIDER .Values.storage.provider $secretEnv.STORAGE_PROVIDER $env.STORAGE_PROVIDER | default "" | toString | trim | lower -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else if coalesce .Values.storage.s3.bucket $env.EVIDENCE_S3_BUCKET $env.S3_BUCKET $secretEnv.EVIDENCE_S3_BUCKET $secretEnv.S3_BUCKET -}}
s3
{{- end -}}
{{- end -}}

{{- define "grick.storage.localAllowed" -}}
{{- if and .Values.storage.allowLocal (eq (include "grick.storage.provider" .) "local" "") -}}true{{- end -}}
{{- end -}}

{{/*
Fail rendering when evidence would land on local disk without an explicit,
single-replica opt-in. /readyz fails in production on local storage, and the
root filesystem is read-only. When env comes from existingSecret,
externalSecret or extraEnvFrom the chart cannot see the provider, so it does
not fail; /readyz still reports a missing object store.
*/}}
{{- define "grick.storage.validate" -}}
{{- $provider := include "grick.storage.provider" . -}}
{{- if not (has $provider (list "s3" "aws-s3" "s3-bucket" "azure" "azure-blob")) -}}
{{- if not (has $provider (list "" "local")) -}}
{{- fail (printf "storage.provider %q is not supported. Use s3 or azure-blob." $provider) -}}
{{- end -}}
{{- $external := or .Values.existingSecret .Values.externalSecret.enabled .Values.extraEnvFrom -}}
{{- if and (not .Values.storage.allowLocal) (not $external) -}}
{{- fail "No evidence object store is configured. Set storage.provider=s3 with storage.s3.bucket, or storage.provider=azure-blob with storage.azure.containerName. Local disk storage needs storage.allowLocal=true and replicaCount=1." -}}
{{- end -}}
{{- if and .Values.storage.allowLocal (ne (int .Values.replicaCount) 1) -}}
{{- fail (printf "storage.allowLocal=true keeps evidence on per-pod disk, which needs replicaCount=1 (got %d). Use storage.provider=s3 or azure-blob for more replicas." (int .Values.replicaCount)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Storage keys for the ConfigMap. Keys already set in .Values.env win, so
existing overlays keep their values and no key is emitted twice.
*/}}
{{- define "grick.storage.configData" -}}
{{- $env := .Values.env | default dict -}}
{{- $data := dict -}}
{{- with .Values.storage.provider }}{{ $_ := set $data "EVIDENCE_STORAGE_PROVIDER" . }}{{ end -}}
{{- with .Values.storage.s3.bucket }}{{ $_ := set $data "EVIDENCE_S3_BUCKET" . }}{{ end -}}
{{- with .Values.storage.s3.region }}{{ $_ := set $data "EVIDENCE_S3_REGION" . }}{{ end -}}
{{- with .Values.storage.azure.containerName }}{{ $_ := set $data "AZURE_STORAGE_CONTAINER_NAME" . }}{{ end -}}
{{- if include "grick.storage.localAllowed" . -}}
{{- $_ := set $data "ALLOW_LOCAL_EVIDENCE_STORAGE" "true" -}}
{{- $_ := set $data "EVIDENCE_STORAGE_PATH" .Values.storage.local.path -}}
{{- end -}}
{{- range $key, $value := $data }}
{{- if not (hasKey $env $key) }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "grick.storage.volumeMount" -}}
{{- if include "grick.storage.localAllowed" . }}
- name: evidence
  mountPath: {{ .Values.storage.local.path }}
{{- end }}
{{- end -}}

{{- define "grick.storage.volume" -}}
{{- if include "grick.storage.localAllowed" . }}
- name: evidence
{{- if .Values.storage.local.existingClaim }}
  persistentVolumeClaim:
    claimName: {{ .Values.storage.local.existingClaim }}
{{- else }}
  # Not durable: evidence is lost when the pod is rescheduled. Set
  # storage.local.existingClaim to keep it.
  emptyDir: {}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Pod annotations: a checksum of the rendered ConfigMap and Secret, so a
`helm upgrade` that only changes env or secretEnv still rolls the pods, merged
with .Values.podAnnotations.
*/}}
{{- define "grick.podAnnotations" -}}
checksum/config: {{ include (print .Template.BasePath "/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print .Template.BasePath "/secret.yaml") . | sha256sum }}
{{- with .Values.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "grick.secretName" -}}
{{- default (printf "%s-secrets" (include "grick.fullname" .)) .Values.existingSecret -}}
{{- end -}}
