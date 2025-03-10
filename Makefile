# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 3.11.1
# Replaces Operator version
# Set this when when there is a new patch release in the channel.
REPLACES_VERSION ?= none

LOCAL_BIN ?= $(PWD)/ci-tools/bin
export PATH := $(LOCAL_BIN):$(PATH)

# Detect the OS to set per-OS defaults
GOOS := $(shell go env GOOS)
GOARCH := $(shell go env GOARCH)

# Fix sed issues on mac by using GSED and fix base64 issues on macos by omitting the -w 0 parameter
SED="sed"
ifeq ($(GOOS), darwin)
  SED="gsed"
endif

get-replaces-version:
	@echo $(REPLACES_VERSION)

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
CHANNELS ?= stable,3.11
ifneq ($(origin CHANNELS), undefined)
  BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
DEFAULT_CHANNEL ?= stable
ifneq ($(origin DEFAULT_CHANNEL), undefined)
  BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)
# Option to use podman or docker
DOCKER ?= docker

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# gatekeeper.sh/gatekeeper-operator-bundle:$VERSION and gatekeeper.sh/gatekeeper-operator-catalog:$VERSION.
REPO ?= quay.io/gatekeeper
IMAGE_TAG_BASE ?= $(REPO)/gatekeeper-operator

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v$(VERSION)

# Image URL to use all building/pushing image targets
IMG ?= $(IMAGE_TAG_BASE):v$(VERSION)
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true,preserveUnknownFields=false"
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.21

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
  GOBIN=$(shell go env GOPATH)/bin
else
  GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

clean: ## Clean up build artifacts.
	rm $(LOCAL_BIN)/*

##@ Development

CONTROLLER_GEN = $(LOCAL_BIN)/controller-gen
KUSTOMIZE = $(LOCAL_BIN)/kustomize
ENVTEST = $(LOCAL_BIN)/setup-envtest
GO_BINDATA = $(LOCAL_BIN)/go-bindata
KUSTOMIZE_VERSION ?= v5.0.1
OPM_VERSION ?= v1.27.0
GO_BINDATA_VERSION ?= v3.1.2+incompatible
BATS_VERSION ?= 1.2.1
OLM_VERSION ?= v0.18.2
KUBERNETES_VERSION ?= v1.26.4

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases output:rbac:dir=config/rbac

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	GOFLAGS=$(GOFLAGS) go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	GOFLAGS=$(GOFLAGS) go vet ./...

.PHONY: tidy
tidy: ## Run go mod tidy
	GO111MODULE=on GOFLAGS=$(GOFLAGS) go mod tidy

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" GOFLAGS=$(GOFLAGS) go test ./... -coverprofile cover.out

.PHONY: test-e2e
test-e2e: generate fmt vet ## Run e2e tests, using the configured Kubernetes cluster in ~/.kube/config
	GOFLAGS=$(GOFLAGS) USE_EXISTING_CLUSTER=true go test -v ./test/e2e -coverprofile cover.out -race -args -ginkgo.v -ginkgo.progress -ginkgo.trace -namespace $(NAMESPACE) -timeout 5m -delete-timeout 10m

.PHONY: test-cluster
test-cluster: ## Create a local kind cluster with a registry for testing
	KIND_CLUSTER_VERSION=$(KUBERNETES_VERSION) ./scripts/kind-with-registry.sh

.PHONY: test-gatekeeper-e2e
test-gatekeeper-e2e: ## Applies the test yaml and verifies that BATS is installed. For use by GitHub Actions
	kubectl -n $(NAMESPACE) apply -f ./config/samples/gatekeeper_e2e_test.yaml
	bats --version

.PHONY: download-binaries
download-binaries: kustomize go-bindata envtest controller-gen
	mkdir -p $(LOCAL_BIN)
	# Download and install bats
	curl -sSLO https://github.com/bats-core/bats-core/archive/v${BATS_VERSION}.tar.gz && tar -zxvf v${BATS_VERSION}.tar.gz && bash bats-core-${BATS_VERSION}/install.sh $(PWD)/ci-tools
	rm -rf bats-core-${BATS_VERSION} v${BATS_VERSION}.tar.gz

##@ Build

.PHONY: build
build: generate fmt vet ## Build manager binary.
	CGO_ENABLED=1 GOFLAGS=$(GOFLAGS) go build -ldflags $(LDFLAGS) -o bin/manager main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host, using the configured Kubernetes cluster in ~/.kube/config
	GOFLAGS=$(GOFLAGS) GATEKEEPER_TARGET_NAMESPACE=$(NAMESPACE) go run -ldflags $(LDFLAGS) ./main.go

.PHONY: docker-build
docker-build: test ## Build docker image with the manager.
	$(DOCKER) build --build-arg GOOS=${GOOS} --build-arg GOARCH=${GOARCH} --build-arg LDFLAGS=${LDFLAGS} -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(DOCKER) push ${IMG}

BINDATA_OUTPUT_FILE := ./pkg/bindata/bindata.go

.PHONY: go-bindata
go-bindata:
	$(call go-get-tool,github.com/go-bindata/go-bindata/go-bindata@${GO_BINDATA_VERSION})

.PHONY: .run-bindata
.run-bindata: go-bindata
	mkdir -p ./$(GATEKEEPER_MANIFEST_DIR)-rendered && \
	$(KUSTOMIZE) build $(GATEKEEPER_MANIFEST_DIR) -o ./$(GATEKEEPER_MANIFEST_DIR)-rendered && \
	$(GO_BINDATA) -nocompress -nometadata \
		-prefix "bindata" \
		-pkg "bindata" \
		-o "$${BINDATA_OUTPUT_PREFIX}$(BINDATA_OUTPUT_FILE)" \
		-ignore "OWNERS" \
		./$(GATEKEEPER_MANIFEST_DIR)-rendered/... && \
	rm -rf ./$(GATEKEEPER_MANIFEST_DIR)-rendered && \
	gofmt -s -w "$${BINDATA_OUTPUT_PREFIX}$(BINDATA_OUTPUT_FILE)"

.PHONY: update-bindata
update-bindata:
	$(MAKE) .run-bindata ;\

.PHONY: verify-bindata
verify-bindata:
	export TMP_DIR=$$(mktemp -d) ;\
	export BINDATA_OUTPUT_PREFIX="$${TMP_DIR}/" ;\
	$(MAKE) .run-bindata ;\
	if ! diff -Naup {.,$${TMP_DIR}}/$(BINDATA_OUTPUT_FILE); then \
		echo "Error: $(BINDATA_OUTPUT_FILE) and $${TMP_DIR}/$(BINDATA_OUTPUT_FILE) files differ. Run 'make update-bindata' and try again." ;\
		rm -rf "$${TMP_DIR}" ;\
		exit 1 ;\
	fi ;\
	rm -rf "$${TMP_DIR}" ;\

.PHONY: release
release: manifests kustomize
	cd config/default && $(KUSTOMIZE) edit set namespace $(NAMESPACE)
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default > ./deploy/gatekeeper-operator.yaml

##@ Deployment

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/default && $(KUSTOMIZE) edit set namespace $(NAMESPACE)
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | kubectl delete -f -

.PHONY: deploy-ci
deploy-ci: install patch-image deploy ## Deploys the controller with a patched pull policy.

.PHONY: deploy-olm
deploy-olm:
	$(OPERATOR_SDK) olm install --version $(OLM_VERSION) --timeout 5m

.PHONY: deploy-using-olm
deploy-using-olm:
	$(SED) -i 's#quay.io/gatekeeper/gatekeeper-operator-bundle-index:latest#$(BUNDLE_INDEX_IMG)#g' config/olm-install/install-resources.yaml
	$(SED) -i 's#mygatekeeper#$(NAMESPACE)#g' config/olm-install/install-resources.yaml
	$(SED) -i 's#channel: stable#channel: $(DEFAULT_CHANNEL)#g' config/olm-install/install-resources.yaml
	$(KUSTOMIZE) build config/olm-install  | kubectl apply -f -

.PHONY: patch-image
patch-image: ## Patches the manager's image pull policy to be IfNotPresent.
	$(SED) -i 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' config/manager/manager.yaml

.PHONY: controller-gen
controller-gen: ## Download controller-gen locally if necessary.
	$(call go-get-tool,sigs.k8s.io/controller-tools/cmd/controller-gen@v0.6.1)

.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,sigs.k8s.io/kustomize/kustomize/v5@${KUSTOMIZE_VERSION})

.PHONY: envtest
envtest: ## Download envtest-setup locally if necessary.
	$(call go-get-tool,sigs.k8s.io/controller-runtime/tools/setup-envtest@latest)

# go-get-tool will 'go install' any package $1 and install it to LOCAL_BIN.
define go-get-tool
  @set -e ;\
  echo "Checking installation of $(1)" ;\
  GOBIN=$(LOCAL_BIN) go install $(1)
endef

##@ Operator Bundling

.PHONY: bundle
bundle: operator-sdk manifests kustomize ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	VERSION=$(VERSION) ;\
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle -q --overwrite --version $${VERSION/v/} $(BUNDLE_METADATA_OPTS)
	$(SED) -i 's/base64data: \"\"/base64data: \"PHN2ZyBpZD0iZjc0ZTM5ZDEtODA2Yy00M2E0LTgyZGQtZjM3ZjM1NWQ4YWYzIiBkYXRhLW5hbWU9Ikljb24iIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgdmlld0JveD0iMCAwIDM2IDM2Ij4KICA8ZGVmcz4KICAgIDxzdHlsZT4KICAgICAgLmE0MWM1MjM0LWExNGEtNGYzZC05MTYwLTQ0NzJiNzZkMDA0MCB7CiAgICAgICAgZmlsbDogI2UwMDsKICAgICAgfQogICAgPC9zdHlsZT4KICA8L2RlZnM+CiAgPGc+CiAgICA8cGF0aCBjbGFzcz0iYTQxYzUyMzQtYTE0YS00ZjNkLTkxNjAtNDQ3MmI3NmQwMDQwIiBkPSJNMjUsMTcuMzhIMjMuMjNhNS4yNyw1LjI3LDAsMCwwLTEuMDktMi42NGwxLjI1LTEuMjVhLjYyLjYyLDAsMSwwLS44OC0uODhsLTEuMjUsMS4yNWE1LjI3LDUuMjcsMCwwLDAtMi42NC0xLjA5VjExYS42Mi42MiwwLDEsMC0xLjI0LDB2MS43N2E1LjI3LDUuMjcsMCwwLDAtMi42NCwxLjA5bC0xLjI1LTEuMjVhLjYyLjYyLDAsMCwwLS44OC44OGwxLjI1LDEuMjVhNS4yNyw1LjI3LDAsMCwwLTEuMDksMi42NEgxMWEuNjIuNjIsMCwwLDAsMCwxLjI0aDEuNzdhNS4yNyw1LjI3LDAsMCwwLDEuMDksMi42NGwtMS4yNSwxLjI1YS42MS42MSwwLDAsMCwwLC44OC42My42MywwLDAsMCwuODgsMGwxLjI1LTEuMjVhNS4yNyw1LjI3LDAsMCwwLDIuNjQsMS4wOVYyNWEuNjIuNjIsMCwwLDAsMS4yNCwwVjIzLjIzYTUuMjcsNS4yNywwLDAsMCwyLjY0LTEuMDlsMS4yNSwxLjI1YS42My42MywwLDAsMCwuODgsMCwuNjEuNjEsMCwwLDAsMC0uODhsLTEuMjUtMS4yNWE1LjI3LDUuMjcsMCwwLDAsMS4wOS0yLjY0SDI1YS42Mi42MiwwLDAsMCwwLTEuMjRabS03LDQuNjhBNC4wNiw0LjA2LDAsMSwxLDIyLjA2LDE4LDQuMDYsNC4wNiwwLDAsMSwxOCwyMi4wNloiLz4KICAgIDxwYXRoIGNsYXNzPSJhNDFjNTIzNC1hMTRhLTRmM2QtOTE2MC00NDcyYjc2ZDAwNDAiIGQ9Ik0yNy45LDI4LjUyYS42Mi42MiwwLDAsMS0uNDQtLjE4LjYxLjYxLDAsMCwxLDAtLjg4LDEzLjQyLDEzLjQyLDAsMCwwLDIuNjMtMTUuMTkuNjEuNjEsMCwwLDEsLjMtLjgzLjYyLjYyLDAsMCwxLC44My4yOSwxNC42NywxNC42NywwLDAsMS0yLjg4LDE2LjYxQS42Mi42MiwwLDAsMSwyNy45LDI4LjUyWiIvPgogICAgPHBhdGggY2xhc3M9ImE0MWM1MjM0LWExNGEtNGYzZC05MTYwLTQ0NzJiNzZkMDA0MCIgZD0iTTI3LjksOC43M2EuNjMuNjMsMCwwLDEtLjQ0LS4xOUExMy40LDEzLjQsMCwwLDAsMTIuMjcsNS45MWEuNjEuNjEsMCwwLDEtLjgzLS4zLjYyLjYyLDAsMCwxLC4yOS0uODNBMTQuNjcsMTQuNjcsMCwwLDEsMjguMzQsNy42NmEuNjMuNjMsMCwwLDEtLjQ0LDEuMDdaIi8+CiAgICA8cGF0aCBjbGFzcz0iYTQxYzUyMzQtYTE0YS00ZjNkLTkxNjAtNDQ3MmI3NmQwMDQwIiBkPSJNNS4zNSwyNC42MmEuNjMuNjMsMCwwLDEtLjU3LS4zNUExNC42NywxNC42NywwLDAsMSw3LjY2LDcuNjZhLjYyLjYyLDAsMCwxLC44OC44OEExMy40MiwxMy40MiwwLDAsMCw1LjkxLDIzLjczYS42MS42MSwwLDAsMS0uMy44M0EuNDguNDgsMCwwLDEsNS4zNSwyNC42MloiLz4KICAgIDxwYXRoIGNsYXNzPSJhNDFjNTIzNC1hMTRhLTRmM2QtOTE2MC00NDcyYjc2ZDAwNDAiIGQ9Ik0xOCwzMi42MkExNC42NCwxNC42NCwwLDAsMSw3LjY2LDI4LjM0YS42My42MywwLDAsMSwwLS44OC42MS42MSwwLDAsMSwuODgsMCwxMy40MiwxMy40MiwwLDAsMCwxNS4xOSwyLjYzLjYxLjYxLDAsMCwxLC44My4zLjYyLjYyLDAsMCwxLS4yOS44M0ExNC42NywxNC42NywwLDAsMSwxOCwzMi42MloiLz4KICAgIDxwYXRoIGNsYXNzPSJhNDFjNTIzNC1hMTRhLTRmM2QtOTE2MC00NDcyYjc2ZDAwNDAiIGQ9Ik0zMCwyOS42MkgyN2EuNjIuNjIsMCwwLDEtLjYyLS42MlYyNmEuNjIuNjIsMCwwLDEsMS4yNCwwdjIuMzhIMzBhLjYyLjYyLDAsMCwxLDAsMS4yNFoiLz4KICAgIDxwYXRoIGNsYXNzPSJhNDFjNTIzNC1hMTRhLTRmM2QtOTE2MC00NDcyYjc2ZDAwNDAiIGQ9Ik03LDMwLjYyQS42Mi42MiwwLDAsMSw2LjM4LDMwVjI3QS42Mi42MiwwLDAsMSw3LDI2LjM4aDNhLjYyLjYyLDAsMCwxLDAsMS4yNEg3LjYyVjMwQS42Mi42MiwwLDAsMSw3LDMwLjYyWiIvPgogICAgPHBhdGggY2xhc3M9ImE0MWM1MjM0LWExNGEtNGYzZC05MTYwLTQ0NzJiNzZkMDA0MCIgZD0iTTI5LDkuNjJIMjZhLjYyLjYyLDAsMCwxLDAtMS4yNGgyLjM4VjZhLjYyLjYyLDAsMCwxLDEuMjQsMFY5QS42Mi42MiwwLDAsMSwyOSw5LjYyWiIvPgogICAgPHBhdGggY2xhc3M9ImE0MWM1MjM0LWExNGEtNGYzZC05MTYwLTQ0NzJiNzZkMDA0MCIgZD0iTTksMTAuNjJBLjYyLjYyLDAsMCwxLDguMzgsMTBWNy42Mkg2QS42Mi42MiwwLDAsMSw2LDYuMzhIOUEuNjIuNjIsMCwwLDEsOS42Miw3djNBLjYyLjYyLDAsMCwxLDksMTAuNjJaIi8+CiAgPC9nPgo8L3N2Zz4K\"/g' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
	$(SED) -i 's/mediatype: \"\"/mediatype: \"image\/svg+xml\"/g' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
	$(SED) -i 's/^  version:.*/  version: "$(VERSION)"/' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
	$(SED) -i '/^    createdAt:.*/d' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
	$(SED) -i 's/$(CHANNELS)/"$(CHANNELS)"/g' bundle/metadata/annotations.yaml
  ifneq ($(REPLACES_VERSION), none)
	  $(SED) -i 's/^  replaces:.*/  replaces: gatekeeper-operator.v$(REPLACES_VERSION)/' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
  else
	  $(SED) -i 's/^  replaces:.*/  # replaces: none/' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
	  $(SED) -i 's/^    olm.skipRange:.*/    olm.skipRange: "<$(VERSION)"/' bundle/manifests/gatekeeper-operator.clusterserviceversion.yaml
  endif
	$(OPERATOR_SDK) bundle validate ./bundle

# Requires running cluster (for example through 'make test-cluster')
.PHONY: scorecard
scorecard: bundle
	$(OPERATOR_SDK) scorecard ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	$(DOCKER) build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

OPM = $(LOCAL_BIN)/opm

.PHONY: opm
opm: $(OPM)

$(OPM):
	mkdir -p $(@D)
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/$(OPM_VERSION)/$(GOOS)-$(GOARCH)-opm
	chmod +x $(OPM)

# Path used to import Gatekeeper manifests. For example, this could be a local
# file system directory if kustomize has errors using the GitHub URL. See
# https://github.com/kubernetes-sigs/kustomize/issues/4052
IMPORT_MANIFESTS_PATH ?= https://github.com/open-policy-agent/gatekeeper
TMP_IMPORT_MANIFESTS_PATH := $(shell mktemp -d)

# Import Gatekeeper manifests
.PHONY: import-manifests
import-manifests: kustomize
	if [[ $(IMPORT_MANIFESTS_PATH) =~ https://* ]]; then \
		git clone --branch $(GATEKEEPER_VERSION) $(IMPORT_MANIFESTS_PATH) $(TMP_IMPORT_MANIFESTS_PATH) ; \
		cd $(TMP_IMPORT_MANIFESTS_PATH) && make patch-image ; \
		$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone $(TMP_IMPORT_MANIFESTS_PATH)/config/default -o $(MAKEFILE_DIR)/$(GATEKEEPER_MANIFEST_DIR); \
		rm -rf "$${TMP_IMPORT_MANIFESTS_PATH}" ; \
	else \
		$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone $(IMPORT_MANIFESTS_PATH)/config/default -o $(GATEKEEPER_MANIFEST_DIR); \
	fi

	cd $(GATEKEEPER_MANIFEST_DIR) && $(KUSTOMIZE) edit add resource *.yaml

# Build the bundle index image.
.PHONY: bundle-index-build
bundle-index-build: opm
ifneq ($(REPLACES_VERSION), none)
	$(OPM) index add --bundles $(BUNDLE_IMG) --from-index $(PREV_BUNDLE_INDEX_IMG) --tag $(BUNDLE_INDEX_IMG) -c $(DOCKER)
else
	$(OPM) index add --bundles $(BUNDLE_IMG) --tag $(BUNDLE_INDEX_IMG) -c $(DOCKER)
endif

# Generate and push bundle image and bundle index image
# Note: OPERATOR_VERSION is an arbitrary number and does not need to match any official versions
.PHONY: build-and-push-bundle-images
build-and-push-bundle-images: docker-build docker-push
	$(MAKE) bundle VERSION=$(OPERATOR_VERSION)
	$(MAKE) bundle-build
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)
	$(MAKE) bundle-index-build
	$(MAKE) docker-push IMG=$(BUNDLE_INDEX_IMG)

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
  FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)

# operator-sdk variables
# ======================
OPERATOR_SDK_VERSION ?= v1.28.1
OPERATOR_SDK = $(LOCAL_BIN)/operator-sdk
OPERATOR_SDK_URL := https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$(GOOS)_$(GOARCH)

.PHONY: operator-sdk
operator-sdk: $(OPERATOR_SDK)

$(OPERATOR_SDK):
	mkdir -p $(@D)
	curl -L $(OPERATOR_SDK_URL) -o $(OPERATOR_SDK) || (echo "curl returned $$? trying to fetch operator-sdk"; exit 1)
	chmod +x $(OPERATOR_SDK)

# Current Gatekeeper version
GATEKEEPER_VERSION ?= v3.11.1

# Default bundle index image tag
BUNDLE_INDEX_IMG ?= $(IMAGE_TAG_BASE)-bundle-index:v$(VERSION)
# Default previous bundle index image tag
PREV_BUNDLE_INDEX_IMG ?= quay.io/gatekeeper/gatekeeper-operator-bundle-index:v$(REPLACES_VERSION)
# Default namespace
NAMESPACE ?= gatekeeper-system
# Default Kubernetes distribution
KUBE_DISTRIBUTION ?= vanilla

MAKEFILE_DIR := $(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))
GATEKEEPER_MANIFEST_DIR ?= config/gatekeeper

# Set version variables for LDFLAGS
GIT_VERSION ?= $(shell git describe --match='v*' --always --dirty)
GIT_HASH ?= $(shell git rev-parse HEAD)
BUILDDATE = $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_TREESTATE = "clean"
DIFF = $(shell git diff --quiet >/dev/null 2>&1; if [ $$? -eq 1 ]; then echo "1"; fi)
ifeq ($(DIFF), 1)
  GIT_TREESTATE = "dirty"
endif

VERSION_PKG = "github.com/gatekeeper/gatekeeper-operator/pkg/version"
LDFLAGS = "-X $(VERSION_PKG).gitVersion=$(GIT_VERSION) \
           -X $(VERSION_PKG).gitCommit=$(GIT_HASH) \
           -X $(VERSION_PKG).gitTreeState=$(GIT_TREESTATE) \
           -X $(VERSION_PKG).buildDate=$(BUILDDATE)"
