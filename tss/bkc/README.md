# How to build a custom dlstreamer docker image

## Purpose

The custom docker image is used to solve the problems (e.g. dependency, known issues etc) and making a new quick release.

## Materials

ubuntu24.Dockerfile: new ubuntu24 dockerfile
ubuntu24.Dockerfile.patch: patch for the change on ubuntu24.Dockerfile

## Steps to make 

### Download dlstreamer
```bash
git clone https://github.com/open-edge-platform/dlstreamer.git
cd dlstreamer
git submodule update --init --recursive
```

### Update code
```bash
cd dlstreamer
cp ubuntu24.Dockerfile docker/ubuntu/

or 
git apply ubuntu24.Dockerfile.patch

```

### Build docker image
```bash

docker build -f docker/ubuntu/ubuntu24.Dockerfile -t dlstreamer-ubuntu24-custom .

```
