#!/usr/bin/env bash

set -euo pipefail

BASE64ENCODED_AZURE_ACCOUNT_CREDS=$(base64 ~/crossplane-azure-provider-key.json | tr -d "\n")

cat > azure-provider-config.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: azure-account-creds
  namespace: crossplane-system
type: Opaque
data:
  credentials: ${BASE64ENCODED_AZURE_ACCOUNT_CREDS}
---
apiVersion: azure.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: azure-account-creds
      key: credentials
EOF
