# Deploy Base Image

This image is used as a base for Horizon, Minion, and Sentinel Docker containers running in production.
The goal is to provide a small cacheable image which satisfies the dependencies required from the core software.

It provides the following major dependencies:

* Official Ubuntu base image
* OpenJDK JRE (LTS releases)
* JICMP and JICMP6 libraries
* JMX Prometheus exporter
* Some tools from the official apt repository for troubleshooting

It can be built for multiple architectures with Docker and the buildx command.

## Usage

You can build the deploy base image using `make`.
The build targets and arguments are described by running `make help`.

If you just run `make` the goal `oci` will be used for the `linux/amd64` architecture.
The result is an OCI image file in `artifacts/deploy-base-amd64.oci`.
You can load the image with `docker image load -i artifacts/deploy-base-amd64.oci`.

## Registries and tagging

By default the a the registry is set to localhost.
If you want to publish the result to a registry you have to provide at minimum the following arguments:

* `CONTAINER_REGISTRY` as the FQDN, e.g. docker.io or quay.io
* `CONTAINER_REGISTRY_LOGIN` as the user name for the registry
* `CONTAINER_REGISTRY_PASS` as the user name for the registry
* `TAG_ORG` as the organisation name in the registry, e.g. `opennms` or `my-org`
* `VERSION` tag to identify this image build, e.g. `1.0.0`

```
make publish CONTAINER_REGISTRY="quay.io" CONTAINER_REGISTRY_LOGIN="my-login" CONTAINER_REGISTRY_PASS="my-pass" TAG_ORG="my-org" VERSION="1.0.0"
```

If you want to build a container image for a different architecture for example for ARM v7 you can set `ARCHITECTURE="linux/arm/v7`.
You can get a list of available build platforms available in your environment when you run `make builder-instance`.

## Releases

In CircleCI releases are only published to DockerHub when changes are pushed to the `master` branch.

## Limitations

For the reason we sign the images you can only build images for a single architecture at a time.
With docker buildx we need to sign and build the multiarchitecture manifest manually.
We use the CircleCI matrix feature setting the architecture argument.
So if you need images for ARM v7, ARM 64 and AMD 64, just run

```
make oci ARCHITECTURE=linux/arm/v7
make oci ARCHITECTURE=linux/arm64
make oci ARCHITECTURE=linux/amd64
```

The OCI file artifacts are prefixed with the architecture.
