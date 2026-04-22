{{/*
Expand the name of the chart.
*/}}
{{- define "discordbot.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "discordbot.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "discordbot.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "discordbot.labels" -}}
helm.sh/chart: {{ include "discordbot.chart" . }}
{{- range $key, $value := .Values.extraLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/name: {{ include "discordbot.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the image URL.
*/}}
{{- define "discordbot.image" -}}
{{- $registry := .Values.image.registry | default "docker.io" }}
{{- $repository := .Values.image.repository }}
{{- if and (not (empty .Values.image.tag)) (not (hasPrefix "sha-" .Values.image.tag)) }}
{{- printf "%s/%s:%s" $registry $repository .Values.image.tag }}
{{- else }}
{{- printf "%s/%s@%s" $registry $repository .Values.image.digest }}
{{- end }}
{{- end }}

{{/*
Return the appropriate API Group/Version.
*/}}
{{- define "discordbot.apiversion" -}}
{{- if .Values.apiWarnings }}
{{- printf "%s/%s" .Values.apiWarnings.apiGroup .Values.apiWarnings.version }}
{{- end }}
{{- end }}