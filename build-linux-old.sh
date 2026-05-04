#!/bin/bash

# Builds artifacts for old versions of Linux (using ubuntu 20.04).
# These artifacts will work with more recent Linux versions as well.
# Requires singularity and docker installed
# Just change SINGULARITY_IMAGES_PATH below to the path to your singularity images

SINGULARITY_IMAGES_PATH=/data/singularity_images
SIF_NAME=cargo-ubuntu-20.04.sif

[[ ! -d $SINGULARITY_IMAGES_PATH ]] && { echo "$SINGULARITY_IMAGES_PATH doit être un dossier existant"; exit 1; }

if [[ ! -f $SINGULARITY_IMAGES_PATH/$SIF_NAME ]];then
    
    SING_DEF=$(mktemp)
    
cat << EOF
Bootstrap: docker
From: ubuntu:20.04

%post
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt install -y build-essential make libssl-dev pkg-config curl


    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    mkdir -p /opt/rustup
    mkdir -p /opt/cargo

    curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path

    chmod -R a+rwX /opt/rustup /opt/cargo

    ln -s /opt/cargo/bin/* /usr/local/bin/


%environment
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    export PATH=/opt/cargo/bin:\$PATH

%labels
    Author Charles Monod-Broca et ChatGPT
    Description "Rocky Linux 9.6 + Rust build environment"

%help
    Environnement Rocky Linux 9.6 avec Rust installé via rustup.
    Utilisable pour compiler des binaires compatibles RHEL/Rocky 9.6.

%runscript
    exec "\$@"
EOF
    > $SING_DEF
    
    singularity build --fakeroot $SINGULARITY_IMAGES_PATH/$SIF_NAME $SING_DEF
    
    rm $SING_DEF
    
fi



singularity exec -B $HOME/.cargo/registry:/opt/cargo/registry $SINGULARITY_IMAGES_PATH/$SIF_NAME cargo build --release
