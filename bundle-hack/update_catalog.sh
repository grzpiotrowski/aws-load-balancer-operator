#!/usr/bin/env bash

# Helper tool to update the catalog artifacts using the latest bundle image
# These generated artifacts are used to build the catalog image
# Pre-requisites: opm

set -euo pipefail

# Source the digest information
source ./container_digest.sh

: ${OPM:=$(command -v opm)}
echo "using opm from ${OPM}"
# check if opm exists
if [ -z "${OPM}" ]; then
  echo "opm is required"
  exit 1
fi

VERSION=$(cat VERSION)
echo "Creating new bundle using image ${BUNDLE_IMAGE_PULLSPEC}..."

# Create the catalog directory structure
dir_catalog="/catalog/aws-load-balancer-operator"

# Copy the existing package.yaml
cp -f /catalog/aws-load-balancer-operator/package.yaml ${dir_catalog}/

# Generate bundle.yaml using opm render
${OPM} render "${BUNDLE_IMAGE_PULLSPEC}" --output=yaml --migrate-level=bundle-object-to-csv-metadata > "${dir_catalog}/bundle.yaml"

# Generate channel.yaml
cat <<EOF > "${dir_catalog}/channel.yaml"
---
entries:
  - name: aws-load-balancer-operator.v${VERSION}
name: stable-v1
package: aws-load-balancer-operator
schema: olm.channel
---
entries:
  - name: aws-load-balancer-operator.v${VERSION}
name: stable-v1.2
package: aws-load-balancer-operator
schema: olm.channel
EOF

echo "Finished running $(basename "$0")"
