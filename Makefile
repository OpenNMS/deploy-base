## 
# Makefile to build deploy base image for OpenNMS production container images
##
.PHONY: help dep Dockerfile builder-instance oci install tag login publish uninstall clean clean-all

# Export make variables to shell
.EXPORT_ALL_VARIABLES:

.DEFAULT_GOAL := oci

SHELL                     := bash -o nounset -o pipefail -o errexit
BUILD_DATE                := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
BASE_IMAGE                := registry.access.redhat.com/ubi9-minimal

DOCKER_BUILDKIT           := 1
DOCKER_CLI_EXPERIMENTAL   := enabled
ARCHITECTURE              := linux/amd64
BUILDER_INSTANCE          := env-deploy-base-oci
TAG_ARCH                  := $(subst /,-,$(subst linux/,,$(ARCHITECTURE)))

JAVA_MAJOR_VERSION        := 11
JAVA_PKG                  := openjdk-$(JAVA_MAJOR_VERSION)-jre-headless
JAVA_HOME                  = /usr/lib/jvm/jre-${JAVA_MAJOR_VERSION}

# Version fallback uses the latest git version tag or the git hash if no git version is set.
# e.g. last git version tag is v1.1.0 -> 1.1.0 is used, otherwise the git hash
VERSION                   ?= ubi9-$(shell cat version.txt | sed -e 's,[\r\n]*,,')
CONTAINER_REGISTRY        ?= localhost
CONTAINER_REGISTRY_LOGIN  ?= unset
CONTAINER_REGISTRY_PASS   ?= unset
TAG_ORG                   ?= unset
TAG_PROJECT               ?= deploy-base
TAG_LABEL                 := jre-$(JAVA_MAJOR_VERSION)-$(TAG_ARCH)
TAG_OCI                   := $(CONTAINER_REGISTRY)/$(TAG_ORG)/$(TAG_PROJECT):$(VERSION)-$(TAG_LABEL)
DOCKER_FLAGS              := 

VCS_SOURCE                := $(shell git remote get-url origin)
VCS_REVISION              := $(shell git describe --always)
BUILD_NUMBER              ?= unset
BUILD_URL                 ?= unset
BUILD_BRANCH              ?= $(shell git branch --show-current)

JICMP_GIT_REPO_URL        := https://github.com/opennms/jicmp
JICMP_VERSION             := jicmp-3.0.0-2

JICMP6_GIT_REPO_URL       := https://github.com/opennms/jicmp6
JICMP6_VERSION            := jicmp6-3.0.0-2

JATTACH_GIT_REPO_URL      := https://github.com/jattach/jattach
JATTACH_VERSION           := v2.1

HAVEGED_GIT_REPO_URL      := https://github.com/jirka-h/haveged

CONFD_SOURCE              := https://github.com/abtreece/confd
CONFD_VERSION             := 0.30.0

PROM_JMX_EXPORTER_VERSION := 1.4.0
PROM_JMX_EXPORTER_URL     := https://github.com/prometheus/jmx_exporter/releases/download/$(PROM_JMX_EXPORTER_VERSION)/jmx_prometheus_javaagent-$(PROM_JMX_EXPORTER_VERSION).jar
PROM_JMX_EXPORTER_SHA256  := "db1492e95a7ee95cd5e0a969875c0d4f0ef6413148d750351a41cc71d775f59a"

PYROSCOPE_VERSION         := "2.1.2"
PYROSCOPE_SHA256          := "bbf88777b8241934ce24447cd6bd1be3f80497d153972d32a716fb21b1e12b32"
PYROSCOPE_URL             := "https://github.com/grafana/pyroscope-java/releases/download/v${PYROSCOPE_VERSION}/pyroscope.jar"

help:
	@echo ""
	@echo "Makefile to build multi-architecture deploy base image and push to a registry."
	@echo ""
	@echo "Requirements to build images:"
	@echo "  * Docker 19+"
	@echo ""
	@echo "Targets:"
	@echo "  help:           Show this help"
	@echo "  dep:            Check if build dependencies are installed"
	@echo "  Dockerfile:     Generate Dockerfile from template"
	@echo "  build-instance: Instantiate a docker buildx instance"
	@echo "  oci:            Create an OCI image file for the given architecture in the artifacts directory"
	@echo "  install:        Load the OCI file in your Docker instance"
	@echo "  tag:            Generate and set the OCI tag"
	@echo "  login:          Login to the container registry"
	@echo "  publish:        Push tagged OCI to the container registry"
	@echo "  uninstall:      Remove the container image from your Docker instance"
	@echo "  clean:          Remove the buildx instance and remove the image from your Docker instance"
	@echo "  clean-all:      Remove the Dockerx build instance, remove Docker image and delete all artifacts from filesystem"
	@echo ""
	@echo "Arguments to modify the build:"
	@echo "  VERSION:                   Version number for this release of the $(TAG_PROJECT) artefact. Value: $(VERSION)"
	@echo "  BASE_IMAGE:                The base image used to build this image. Value: $(BASE_IMAGE)"
	@echo "  BUILDER_INSTANCE:          Name of the docker buildx instance. Value: $(BUILDER_INSTANCE)"
	@echo "  ARCHITECTURE:              Target architecture for the OCI image. Value: $(ARCHITECTURE)"
	@echo "  CONTAINER_REGISTRY:        FQDN of the OCI registry. Value: $(CONTAINER_REGISTRY)"
	@echo "  TAG_ORG:                   Registry organisation name where the image is pushed. Value: $(TAG_ORG)"
	@echo "  TAG_PROJECT:               Name of the image in the registry. Value: $(TAG_PROJECT)"
	@echo "  DOCKER_FLAGS:              Additional docker buildx flags, by default write a single architecture to a file. Value: $(DOCKER_FLAGS)"
	@echo "  BUILD_NUMBER:              In case we run in CI/CD this is the build number which produced the artifact. Value: $(BUILD_NUMBER)"
	@echo "  BUILD_URL:                 In case we run in CI/CD this is the URL which for the build. Value: $(BUILD_URL)"
	@echo "  BUILD_BRANCH:              In case we run in CI/CD this is the branch of the build. Value: $(BUILD_BRANCH)"
	@echo ""
	@echo "Example:"
	@echo "  Create a local OCI file make oci ARCHITECTURE=linux/arm/v7" 
	@echo "  make tag CONTAINER_REGISTRY=myregistry.com TAG_ORG=myorg DOCKER_FLAGS=--push"

dep:
	@echo "Ensure envsubst is available ..."
	@command -v envsubst
	@echo "Test Docker and Buildx installation ..."
	@command -v docker
	@docker --version
	@echo "Image Tag: $(TAG_OCI)"
	@echo ""
	@docker info

Dockerfile: dep
	@echo "Generate Dockerfile from template"
	@echo "##" > Dockerfile
	@echo "# DO NOT EDIT: This file is generated from the Dockerfile.tpl" >> Dockerfile
	@echo "##" >> Dockerfile
	@echo "" >> Dockerfile
	envsubst < "Dockerfile.tpl" >> "Dockerfile"

builder-instance: dep
	@if ! docker buildx inspect "$(BUILDER_INSTANCE)"; then docker buildx create --name "$(BUILDER_INSTANCE)"; fi;
	@docker buildx use "$(BUILDER_INSTANCE)"

oci: Dockerfile builder-instance
	@echo "Build container image for architecture: $(ARCHITECTURE) ..."
	@mkdir -p artifacts
	@docker buildx build --progress=plain --output=type=docker,dest=artifacts/$(TAG_PROJECT)-$(TAG_LABEL).oci --platform="$(ARCHITECTURE)" --tag=$(TAG_PROJECT):$(TAG_LABEL) $(DOCKER_FLAGS) . ;

install: oci
	@echo "Load image ..."
	@docker image load -i artifacts/$(TAG_PROJECT)-$(TAG_LABEL).oci;

tag: install
	@echo "Tag Docker image ..."
	@docker tag $(TAG_PROJECT):$(TAG_LABEL) $(TAG_OCI)

login: dep
	@echo "Login to ${CONTAINER_REGISTRY}: "
	@echo "${CONTAINER_REGISTRY_PASS}" | docker login ${CONTAINER_REGISTRY} -u "${CONTAINER_REGISTRY_LOGIN}" --password-stdin > /dev/null

publish: oci tag
	@echo -n "Verify image tag in registry for $(TAG_OCI) ... "
	@if docker manifest inspect "$(TAG_OCI)" >/dev/null; then echo -e "\033[0;31mFAIL\033[0m"; echo "Image tag already published on registry."; exit 1; fi;
	@echo "Push Docker image to registry: $(TAG_OCI) ..."
	@docker push ${TAG_OCI}

uninstall: dep
	@echo "Remove image ..."
	@docker rmi $(TAG_PROJECT):$(TAG_LABEL) || exit 0
	@docker rmi $(TAG_OCI) || exit 0

clean: uninstall
	@echo "Destroy builder environment: $(BUILDER_INSTANCE) ..."
	@docker buildx rm $(BUILDER_INSTANCE);

clean-all: clean
	@echo "Delete artifacts ..."
	@rm Dockerfile
	@rm -rf artifacts
