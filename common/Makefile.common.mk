#!/bin/bash
#
# Copyright 2021 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

############################################################
# GKE section
############################################################
PROJECT ?= oceanic-guard-191815
ZONE    ?= us-west1-a
CLUSTER ?= prow
NAMESPACESCOPE_VERSION = 1.1.1
OLM_API_VERSION = 0.3.8

activate-serviceaccount:
ifdef GOOGLE_APPLICATION_CREDENTIALS
	gcloud auth activate-service-account --key-file="$(GOOGLE_APPLICATION_CREDENTIALS)"
endif

get-cluster-credentials: activate-serviceaccount
	gcloud container clusters get-credentials "$(CLUSTER)" --project="$(PROJECT)" --zone="$(ZONE)"

config-docker: get-cluster-credentials
	@common/scripts/artifactory_config_docker.sh

config-docker-quay: get-cluster-credentials
	@common/scripts/quay_config_docker.sh

# find or download operator-sdk
# download operator-sdk if necessary
operator-sdk:
ifeq (, $(OPERATOR_SDK))
	@./common/scripts/install-operator-sdk.sh
OPERATOR_SDK=/usr/local/bin/operator-sdk
endif

# find or download kubebuilder
# download kubebuilder if necessary
kube-builder:
ifeq (, $(wildcard /usr/local/kubebuilder))
	@./common/scripts/install-kubebuilder.sh
endif

# find or download opm
# download opm if necessary
opm:
ifeq (,$(OPM))
	@./common/scripts/install-opm.sh
endif

fetch-test-crds:
	@{ \
	curl -L -O "https://github.com/operator-framework/api/archive/v${OLM_API_VERSION}.tar.gz" ;\
	tar -zxf v${OLM_API_VERSION}.tar.gz api-${OLM_API_VERSION}/crds && mv api-${OLM_API_VERSION}/crds/* ${ENVCRDS_DIR} ;\
	rm -rf api-${OLM_API_VERSION} v${OLM_API_VERSION}.tar.gz ;\
	}
	@{ \
	curl -L -O "https://github.com/horis233/jenkins-operator/archive/v0.3.3.tar.gz" ;\
	tar -zxf v0.3.3.tar.gz jenkins-operator-0.3.3/deploy/crds && mv jenkins-operator-0.3.3/deploy/crds/jenkins_v1alpha2_jenkins_crd.yaml ${ENVCRDS_DIR}/jenkins_v1alpha2_jenkins_crd.yaml ;\
	rm -rf jenkins-operator-0.3.3 v0.3.3.tar.gz ;\
	}
	@{ \
	curl -L -O "https://github.com/horis233/etcd-operator/archive/v0.9.4-crd.tar.gz" ;\
	tar -zxf v0.9.4-crd.tar.gz etcd-operator-0.9.4-crd/deploy/crds && mv etcd-operator-0.9.4-crd/deploy/crds/etcdclusters.etcd.database.coreos.com.crd.yaml ${ENVCRDS_DIR}/etcdclusters.etcd.database.coreos.com.crd.yaml ;\
	rm -rf etcd-operator-0.9.4-crd v0.9.4-crd.tar.gz ;\
	}
	@{ \
	curl -L -O "https://github.com/IBM/ibm-namespace-scope-operator/archive/v${NAMESPACESCOPE_VERSION}.tar.gz" ;\
	tar -zxf v${NAMESPACESCOPE_VERSION}.tar.gz ibm-namespace-scope-operator-${NAMESPACESCOPE_VERSION}/bundle/manifests && mv ibm-namespace-scope-operator-${NAMESPACESCOPE_VERSION}/bundle/manifests/operator.ibm.com_namespacescopes.yaml ${ENVCRDS_DIR}/operator.ibm.com_namespacescopes.yaml ;\
	rm -rf ibm-namespace-scope-operator-${NAMESPACESCOPE_VERSION} v${NAMESPACESCOPE_VERSION}.tar.gz ;\
	}


CONTROLLER_GEN ?= $(shell pwd)/common/bin/controller-gen
controller-gen: ## Download controller-gen locally if necessary.
	$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.6.1)

KUSTOMIZE ?= $(shell pwd)/common/bin/kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v3@v3.8.7)

KIND ?= $(shell pwd)/common/bin/kind
kind: ## Download kind locally if necessary.
	$(call go-get-tool,$(KIND),sigs.k8s.io/kind@v0.10.0)

ENVTEST = $(shell pwd)/common/bin/setup-envtest
setup-envtest: ## Download envtest-setup locally if necessary.
	$(call go-get-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest@latest)

FINDFILES=find . \( -path ./.git -o -path ./.github -o -path ./testcrds \) -prune -o -type f
XARGS = xargs -0 ${XARGS_FLAGS}
CLEANXARGS = xargs ${XARGS_FLAGS}

lint-copyright-banner:
	@${FINDFILES} \( -name '*.go' -o -name '*.cc' -o -name '*.h' -o -name '*.proto' -o -name '*.py' -o -name '*.sh' \) \( ! \( -name '*.gen.go' -o -name '*.pb.go' -o -name '*_pb2.py' \) \) -print0 |\
		${XARGS} common/scripts/lint_copyright_banner.sh

lint-go:
	@${FINDFILES} -name '*.go' \( ! \( -name '*.gen.go' -o -name '*.pb.go' \) \) -print0 | ${XARGS} common/scripts/lint_go.sh

lint-all: lint-copyright-banner lint-go

# Run go vet for this project. More info: https://golang.org/cmd/vet/
code-vet:
	@echo go vet
	go vet $$(go list ./...)

# Run go fmt for this project
code-fmt:
	@echo go fmt
	go fmt $$(go list ./...)

# Run go mod tidy to update dependencies
code-tidy:
	@echo go mod tidy
	go mod tidy -v

# go-get-tool will 'go get' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
unset GOSUMDB ;\
go env -w GOSUMDB=off ;\
GOBIN=$(PROJECT_DIR)/bin go get $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef

.PHONY: code-vet code-fmt code-tidy code-gen lint-copyright-banner lint-go lint-all config-docker operator-sdk kube-builder opm setup-envtest controller-gen fetch-test-crds kustomize kind
