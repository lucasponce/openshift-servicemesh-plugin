#
# Targets for building and pushing images for deployment into a remote OpenShift cluster.
#

.prepare-ocp-image-registry: .ensure-oc-login
	@if [ "$(shell ${OC} get config.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.managementState}')" != "Managed" ]; then echo "Manually patching image registry operator to ensure it is managed"; ${OC} patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'; sleep 3; fi
	@if [ "$(shell ${OC} get config.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.defaultRoute}')" != "true" ]; then echo "Manually patching image registry operator to expose the cluster internal image registry"; ${OC} patch config.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge; sleep 3; routehost="$$(${OC} get image.config.openshift.io/cluster -o custom-columns=EXT:.status.externalRegistryHostnames[0] --no-headers 2>/dev/null)"; while [ "$${routehost}" == "<none>" -o "$${routehost}" == "" ]; do echo "Waiting for image registry route to start..."; sleep 3; routehost="$$(${OC} get image.config.openshift.io/cluster -o custom-columns=EXT:.status.externalRegistryHostnames[0] --no-headers 2>/dev/null)"; done; fi

.prepare-cluster: .prepare-ocp-image-registry
	@$(eval CLUSTER_REPO_INTERNAL ?= $(shell ${OC} get image.config.openshift.io/cluster -o custom-columns=INT:.status.internalRegistryHostname --no-headers 2>/dev/null))
	@$(eval CLUSTER_REPO ?= $(shell ${OC} get image.config.openshift.io/cluster -o custom-columns=EXT:.status.externalRegistryHostnames[0] --no-headers 2>/dev/null))
	@$(eval CLUSTER_PLUGIN_INTERNAL_NAME ?= ${CLUSTER_REPO_INTERNAL}/${PLUGIN_CONTAINER_NAME})
	@$(eval CLUSTER_PLUGIN_NAME ?= ${CLUSTER_REPO}/${PLUGIN_CONTAINER_NAME})
	@$(eval CLUSTER_PLUGIN_INTERNAL_TAG ?= ${CLUSTER_PLUGIN_INTERNAL_NAME}:${PLUGIN_CONTAINER_VERSION})
	@$(eval CLUSTER_PLUGIN_TAG ?= ${CLUSTER_PLUGIN_NAME}:${PLUGIN_CONTAINER_VERSION})
	@$(eval CLUSTER_OPERATOR_INTERNAL_NAME ?= ${CLUSTER_REPO_INTERNAL}/${OPERATOR_CONTAINER_NAME})
	@$(eval CLUSTER_OPERATOR_NAME ?= ${CLUSTER_REPO}/${OPERATOR_CONTAINER_NAME})
	@$(eval CLUSTER_OPERATOR_INTERNAL_TAG ?= ${CLUSTER_OPERATOR_INTERNAL_NAME}:${OPERATOR_CONTAINER_VERSION})
	@$(eval CLUSTER_OPERATOR_TAG ?= ${CLUSTER_OPERATOR_NAME}:${OPERATOR_CONTAINER_VERSION})
	@$(eval ALL_IMAGES_NAMESPACE ?= $(shell echo ${CLUSTER_OPERATOR_NAME} | sed -e 's/.*\/\(.*\)\/.*/\1/'))
	@if [ "${CLUSTER_REPO_INTERNAL}" == "" -o "${CLUSTER_REPO_INTERNAL}" == "<none>" ]; then echo "Cannot determine OCP internal registry hostname. Make sure you 'oc login' to your cluster."; exit 1; fi
	@if [ "${CLUSTER_REPO}" == "" -o "${CLUSTER_REPO}" == "<none>" ]; then echo "Cannot determine OCP external registry hostname. The OpenShift image registry has not been made available for external client access"; exit 1; fi
	@echo "OCP repos: external=[${CLUSTER_REPO}] internal=[${CLUSTER_REPO_INTERNAL}]"
	@${OC} get namespace ${ALL_IMAGES_NAMESPACE} &> /dev/null || \
	  ${OC} create namespace ${ALL_IMAGES_NAMESPACE} &> /dev/null
	@# Add image-puller role so the operator pod can pull the operator image from the internal image registry
	@${OC} policy add-role-to-group system:image-puller system:serviceaccounts:${OPERATOR_NAMESPACE} --namespace=${ALL_IMAGES_NAMESPACE} &> /dev/null
	@# We need to make sure the 'default' service account is created - we'll need it later for the pull secret
	@for i in {1..5}; do ${OC} get sa default -n ${ALL_IMAGES_NAMESPACE} &> /dev/null && break || echo -n "." && sleep 1; done; echo

.prepare-operator-pull-secret: .prepare-cluster
	@# base64 encode a pull secret (using the logged in user token) that can be used to pull the bundle index image from the internal image registry
	@$(eval OPERATOR_IMAGE_PULL_SECRET_JSON = $(shell ${OC} registry login --registry="$(shell ${OC} registry info --internal)" --namespace=${ALL_IMAGES_NAMESPACE} --to=- | base64 -w0))
	@$(eval OPERATOR_IMAGE_PULL_SECRET_NAME ?= ossmplugin-operator-pull-secret)

.create-operator-pull-secret: .prepare-operator-pull-secret
	@if [ -n "${OPERATOR_IMAGE_PULL_SECRET_JSON}" ] && ! (${OC} get secret ${OPERATOR_IMAGE_PULL_SECRET_NAME} --namespace ${OPERATOR_NAMESPACE} &> /dev/null); then \
		echo "${OPERATOR_IMAGE_PULL_SECRET_JSON}" | base64 -d > /tmp/ossmplugin-operator-pull-secret.json ;\
		${OC} get namespace ${OPERATOR_NAMESPACE} &> /dev/null || ${OC} create namespace ${OPERATOR_NAMESPACE} ;\
		${OC} create secret generic ${OPERATOR_IMAGE_PULL_SECRET_NAME} --from-file=.dockerconfigjson=/tmp/ossmplugin-operator-pull-secret.json --type=kubernetes.io/dockerconfigjson --namespace=${OPERATOR_NAMESPACE} ;\
		${OC} label secret ${OPERATOR_IMAGE_PULL_SECRET_NAME} --namespace ${OPERATOR_NAMESPACE} app.kubernetes.io/name=ossmplugin-operator ;\
		rm /tmp/ossmplugin-operator-pull-secret.json ;\
	fi

.remove-operator-pull-secret: .prepare-operator-pull-secret
	${OC} delete --ignore-not-found=true secret ${OPERATOR_IMAGE_PULL_SECRET_NAME} --namespace=${OPERATOR_NAMESPACE}

.prepare-plugin-pull-secret: .prepare-cluster
	@# base64 encode a pull secret (using the logged in user token) that can be used to pull the plugin image from the internal image registry
	@$(eval PLUGIN_IMAGE_PULL_SECRET_JSON = $(shell ${OC} registry login --registry="$(shell ${OC} registry info --internal)" --namespace=${ALL_IMAGES_NAMESPACE} --to=- | base64 -w0))
	@$(eval PLUGIN_IMAGE_PULL_SECRET_NAME ?= ossmplugin-plugin-pull-secret)

.create-plugin-pull-secret: .prepare-plugin-pull-secret
	@if [ -n "${PLUGIN_IMAGE_PULL_SECRET_JSON}" ] && ! (${OC} get secret ${PLUGIN_IMAGE_PULL_SECRET_NAME} --namespace ${PLUGIN_NAMESPACE} &> /dev/null); then \
		echo "${PLUGIN_IMAGE_PULL_SECRET_JSON}" | base64 -d > /tmp/ossmplugin-plugin-pull-secret.json ;\
		${OC} get namespace ${PLUGIN_NAMESPACE} &> /dev/null || ${OC} create namespace ${PLUGIN_NAMESPACE} ;\
		${OC} create secret generic ${PLUGIN_IMAGE_PULL_SECRET_NAME} --from-file=.dockerconfigjson=/tmp/ossmplugin-plugin-pull-secret.json --type=kubernetes.io/dockerconfigjson --namespace=${PLUGIN_NAMESPACE} ;\
		${OC} label secret ${PLUGIN_IMAGE_PULL_SECRET_NAME} --namespace ${PLUGIN_NAMESPACE} app.kubernetes.io/name=ossmplugin ;\
		rm /tmp/ossmplugin-plugin-pull-secret.json ;\
	fi

.remove-plugin-pull-secret: .prepare-plugin-pull-secret
	${OC} delete --ignore-not-found=true secret ${PLUGIN_IMAGE_PULL_SECRET_NAME} --namespace=${PLUGIN_NAMESPACE}

## cluster-status: Outputs details of the client and server for the cluster
cluster-status: .prepare-cluster
	@echo "================================================================="
	@echo "CLUSTER DETAILS"
	@echo "================================================================="
	@echo "Client executable: ${OC}"
	@echo "================================================================="
	${OC} version
	@echo "================================================================="
	@echo "Age of cluster: $(shell ${OC} get namespace kube-system --no-headers | tr -s ' ' | cut -d ' ' -f3)"
	@echo "================================================================="
	@echo "Cluster nodes:"
	@for n in $(shell ${OC} get nodes -o name); do echo "Node=[$${n}]" "CPUs=[$$(${OC} get $${n} -o jsonpath='{.status.capacity.cpu}')] Memory=[$$(${OC} get $${n} -o jsonpath='{.status.capacity.memory}')]"; done
	@echo "================================================================="
	@echo "Console URL: $(shell ${OC} get console cluster -o jsonpath='{.status.consoleURL}' 2>/dev/null)"
	@echo "API Server:  $(shell ${OC} whoami --show-server 2>/dev/null)"
	@echo "================================================================="
	@echo "Operator image as seen from inside the cluster:    ${CLUSTER_OPERATOR_INTERNAL_NAME}"
	@echo "Operator image that will be pushed to the cluster: ${CLUSTER_OPERATOR_TAG}"
	@echo "================================================================="
	@echo "oc whoami -c: $(shell ${OC} whoami -c 2>/dev/null)"
	@echo "================================================================="
ifeq ($(DORP),docker)
	@echo "Image Registry login: docker login -u $(shell ${OC} whoami | tr -d ':')" '-p $$(${OC} whoami -t)' "${CLUSTER_REPO}"
	@echo "================================================================="
else
	@echo "Image Registry login: podman login --tls-verify=false -u $(shell ${OC} whoami | tr -d ':')" '-p $$(${OC} whoami -t)' "${CLUSTER_REPO}"
	@echo "================================================================="
endif

## cluster-build-plugin-image: Builds the plugin image for development with a remote cluster
cluster-build-plugin-image: .prepare-cluster build-plugin-image
	@echo Re-tag the already built plugin image
	${DORP} tag ${PLUGIN_QUAY_TAG} ${CLUSTER_PLUGIN_TAG}

## cluster-push-plugin-image: Builds then pushes the plugin container image to a remote cluster
cluster-push-plugin-image: cluster-build-plugin-image
ifeq ($(DORP),docker)
	@echo Pushing plugin image to remote cluster using docker: ${CLUSTER_PLUGIN_TAG}
	docker push ${CLUSTER_PLUGIN_TAG}
else
	@echo Pushing plugin image to remote cluster using podman: ${CLUSTER_PLUGIN_TAG}
	podman push --tls-verify=false ${CLUSTER_PLUGIN_TAG}
endif

## cluster-build-operator: Builds the operator image for development with a remote cluster
cluster-build-operator: .prepare-cluster build-operator
	@echo Re-tag the already built operator container image
	${DORP} tag ${OPERATOR_QUAY_TAG} ${CLUSTER_OPERATOR_TAG}

## cluster-push-operator: Builds then pushes the operator container image to a remote cluster
cluster-push-operator: cluster-build-operator
ifeq ($(DORP),docker)
	@echo Pushing operator image to remote cluster using docker: ${CLUSTER_OPERATOR_TAG}
	docker push ${CLUSTER_OPERATOR_TAG}
else
	@echo Pushing operator image to remote cluster using podman: ${CLUSTER_OPERATOR_TAG}
	podman push --tls-verify=false ${CLUSTER_OPERATOR_TAG}
endif

## cluster-push: Builds and pushes both the plugin and the operator
cluster-push: cluster-push-plugin-image cluster-push-operator
