#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# SSH to datasets.joyent.com and push all datasets to images.joyent.com.
#
# WARNING: Right now, at least, this should only be used for dev.
# It might eventually be useful for keeping datasets.jo and images.jo in sync.
#

if [ "$TRACE" != "" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


TOP=$(unset CDPATH; cd $(dirname $0)/; pwd)
SSH_OPTIONS="-q -i $HOME/.ssh/automation.id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="ssh $SSH_OPTIONS"
DATASETS_LOGIN=root@datasets.joyent.com



#---- mainline

echo 'Push datasets.joyent.com datasets to images.joyent.com.'
if [[ "$1" != "-f" && "$1" != "--force" ]]; then
    echo '* * *'
    echo '* WARNING: images.joyent.com is a *production* server.'
    echo '* Press <Enter> to continue, <Ctrl+C> to cancel.'
    echo '* * *'
    read
fi

$SSH -T $DATASETS_LOGIN <<SCRIPT

if [ "$TRACE" != "" ]; then
    #export PS4='[\D{%FT%TZ}] \${BASH_SOURCE}:\${LINENO}: \${FUNCNAME[0]:+\${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

export JOYENT_IMGADM_IDENTITY=\$HOME/.ssh/automation.id_rsa
export JOYENT_IMGADM_USER=automation
JOYENT_IMGADM=\$HOME/bin/joyent-imgadm
JSON=\$HOME/bin/json


function push2images {
    local have_uuids=\$(\$JOYENT_IMGADM list -a -j | \$JSON -a uuid)
    local manifests=\$(ls -1 /shared/dsapi/manifests/*.dsmanifest)
    for manifest in \$manifests; do
        local uuid=\$(\$JSON uuid < \$manifest)
        local name=\$(\$JSON name < \$manifest)
        local version=\$(\$JSON version < \$manifest)
        local restricted_to_uuid=\$(\$JSON restricted_to_uuid < \$manifest)
        local type_=\$(\$JSON type < \$manifest)
        if [[ "\$type_" == "vmimage" ]]; then
#            echo "Skipping import of image \$uuid: vmimage type is invalid."
            continue
        elif [[ -n "\$restricted_to_uuid" ]]; then
#            echo "Skipping import of image \$uuid: private."
            continue
        fi
        if [[ -z "\$(echo "\$have_uuids" | grep \$uuid)" ]]; then
            local file=\$(ls /shared/dsapi/assets/\$uuid/*)
            local api_manifest=/var/tmp/\$uuid.dsmanifest
            curl -sS https://datasets.joyent.com/datasets/\$uuid > \$api_manifest
            echo "Importing image \$uuid \$name-\$version into IMGAPI."
            echo "  manifest: \$api_manifest"
            echo "  file:     \$file"
            [[ -f "\$file" ]] || fatal "Image \$uuid file '\$file' not found."
            \$JOYENT_IMGADM import -q -m "\$api_manifest" -f "\$file"
#        else
#            echo "Skipping import of image \$uuid: already in IMGAPI."
        fi
    done
}

# Delete images from images.jo that no longer exist at datasets.jo.
function delimages {
    local ds_uuids=\$(ls /shared/dsapi/manifests/*.dsmanifest | cut -d/ -f5 | cut -d. -f1)
    local img_manifests=\$(\$JOYENT_IMGADM list -a -j)

    local num_manifests=\$(echo "\$img_manifests" | \$JSON length)
    local index=0
    while [[ \$index -lt \$num_manifests ]]; do
        local manifest=\$(echo "\$img_manifests" | \$JSON \$index)
        local uuid=\$(echo "\$manifest" | \$JSON uuid)
        if [[ -z "\$(echo "\$ds_uuids" | grep \$uuid)" ]]; then
            local name=\$(echo "\$manifest" | \$JSON name)
            local version=\$(echo "\$manifest" | \$JSON version)
            echo "Delete image \$uuid (\$name \$version): not in DSAPI."
            \$JOYENT_IMGADM delete \$uuid
        fi
        index=\$((\$index + 1))
    done
}

push2images

# Disabled for now to allow some images.jo-only images, e.g. multiarch.
# There is a skip list of UUIDs in 'ds2imgdiff' to not report on known
# diffs. This means that we'll need to manually delete datasets.jo
# deletions. That's probably a good thing.
#delimages

SCRIPT
