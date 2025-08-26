#!/usr/bin/env bash

set -x
set -e

source ./container_digest.sh

VERSION=$(cat VERSION)
echo "VERSION: ${VERSION}"

source ./bundle_vars.sh

CSV_FILE=${CSV_FILE:-/manifests/aws-load-balancer-operator.clusterserviceversion.yaml}
MANIFESTS_DIR=${MANIFESTS_DIR:-/manifests}
METADATA_DIR=${METADATA_DIR:-/metadata}

OPERATOR_IMAGE_PULLSPEC=${OPERATOR_IMAGE_PULLSPEC:-}
OPERAND_IMAGE_PULLSPEC=${OPERAND_IMAGE_PULLSPEC:-}

REPLACES_VERSION=${REPLACES_VERSION:-}
SUPPORTED_OCP_VERSIONS=${SUPPORTED_OCP_VERSIONS:-}

if [[ -z "${OPERATOR_IMAGE_PULLSPEC}" || -z "${OPERAND_IMAGE_PULLSPEC}" ]]; then
  echo "ERROR: OPERATOR_IMAGE_PULLSPEC and OPERAND_IMAGE_PULLSPEC must be set"
  exit 2
fi

export CSV_FILE MANIFESTS_DIR METADATA_DIR VERSION REPLACES_VERSION SUPPORTED_OCP_VERSIONS
export OPERATOR_IMAGE_PULLSPEC OPERAND_IMAGE_PULLSPEC

# Update direct references in CSV to match release targets
sed -i -e "s|openshift.io/aws-load-balancer-operator:latest|${OPERATOR_IMAGE_PULLSPEC}|g" \
       -e "s|docker.io/amazon/aws-alb-ingress-controller:.*$|${OPERAND_IMAGE_PULLSPEC}|g" \
       -e "s|quay.io/aws-load-balancer-operator/aws-load-balancer-controller:.*$|${OPERAND_IMAGE_PULLSPEC}|g" \
       -e "s|quay.io/aws-load-balancer-operator/aws-load-balancer-controller@.*$|${OPERAND_IMAGE_PULLSPEC}|g" \
       -e "s|gcr.io/kubebuilder/kube-rbac-proxy:.*$|registry.redhat.io/openshift4/ose-kube-rbac-proxy:latest|g" \
       -e "s|quay.io/openshift/origin-kube-rbac-proxy:.*$|registry.redhat.io/openshift4/ose-kube-rbac-proxy:latest|g" "${CSV_FILE}"

export EPOC_TIMESTAMP=$(date +%s)
export TARGET_CSV_FILE="${CSV_FILE}"

python3 - << CSV_UPDATE
import os
from sys import exit as sys_exit
from datetime import datetime
from ruamel.yaml import YAML
yaml = YAML()

def load_manifest(pathn):
   if not pathn.endswith(".yaml"):
      return None
   try:
      with open(pathn, "r") as f:
         return yaml.load(f)
   except FileNotFoundError:
      print("File can not found")
      exit(6)

def dump_manifest(pathn, manifest):
   with open(pathn, "w") as f:
      yaml.dump(manifest, f)
   return
timestamp = int(os.getenv('EPOC_TIMESTAMP'))
datetime_time = datetime.fromtimestamp(timestamp)
version = os.getenv('VERSION')
replaces = os.getenv('REPLACES_VERSION')
operator_pullspec = os.getenv('OPERATOR_IMAGE_PULLSPEC', '')
operand_pullspec = os.getenv('OPERAND_IMAGE_PULLSPEC', '')
csv = load_manifest(os.getenv('TARGET_CSV_FILE'))

# Update metadata
csv['metadata']['annotations']['createdAt'] = datetime_time.strftime('%Y-%m-%dT%H:%M:%S')
csv['metadata']['annotations']['containerImage'] = operator_pullspec
csv['metadata']['name'] = 'aws-load-balancer-operator.v{}'.format(version)
csv['metadata']['annotations']['olm.skipRange'] = '<{}'.format(version)
# All pinned images from CSV will be added to the related images, so we are ready for the disconnected mode
csv['metadata']['annotations']['features.operators.openshift.io/disconnected'] = "true"

# Update spec
csv['spec']['version'] = version
if replaces:
    csv['spec']['replaces'] = 'aws-load-balancer-operator.v{}'.format(replaces)

# Add relatedImages
operator_sha = operator_pullspec.split('@sha256:')[-1] if '@sha256:' in operator_pullspec else 'unknown'
annotation_image_name = f'aws-load-balancer-operator-{operator_sha}-annotation'
csv['spec']['relatedImages'] = [
    {'name': annotation_image_name, 'image': operator_pullspec},
    {'name': 'kube-rbac-proxy', 'image': 'registry.redhat.io/openshift4/ose-kube-rbac-proxy:latest'},
    {'name': 'manager', 'image': operator_pullspec},
    {'name': 'controller', 'image': operand_pullspec}
]
if 'operators.openshift.io/infrastructure-features' in csv['metadata']['annotations']:
    del csv['metadata']['annotations']['operators.openshift.io/infrastructure-features']
dump_manifest(os.getenv('TARGET_CSV_FILE'), csv)
CSV_UPDATE

[ $? -ne 0 ] && { echo "ERROR: Error rendering CSV template."; exit 6; }

# Add OCP annotations.
python3 - << END
import os
from ruamel.yaml import YAML
yaml = YAML()
with open(os.getenv('METADATA_DIR') + "/annotations.yaml", 'r') as f:
    y=yaml.load(f)
    y['annotations']['com.redhat.openshift.versions'] = os.getenv('SUPPORTED_OCP_VERSIONS')
with open(os.getenv('METADATA_DIR') + "/annotations.yaml", 'w') as f:
    yaml.dump(y, f)
END
[ $? -ne 0 ] && { echo "ERROR: Error rendering OCP annotations."; exit 7; }

exit 0
