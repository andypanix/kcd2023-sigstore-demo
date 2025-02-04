
ifndef DOCKER_TAG
	export DOCKER_TAG=1.0.0
endif

##@ Docker

macos-deps:
	brew tap anchore/grype
	brew install kind crane syft cosign grype

clean:
	@kubectx kind-cosign-demo
	kubectl delete -f k8s || true
	kubectl delete -f k8s/policy || true

run: docker-build ## Build the image and run it.
	docker rm -vf nyancat || true
	docker run -d --name nyancat -p 8080:80 $(REGISTRY):$(DOCKER_TAG)

docker-build: ## Build and push the image.
	@echo -n "Building and pushing: $(REGISTRY):$(DOCKER_TAG)\n\n"
	@docker build -t $(REGISTRY):$(DOCKER_TAG) .
	docker push $(REGISTRY):$(DOCKER_TAG)

port-forward:
	kubectl port-forward svc/nyancat 8000:80 

list-registry:
	crane ls $(REGISTRY)

##@ Sigstore
cosign-0: ## Scan the registry.
	crane ls $(REGISTRY)

cosign-1: ## Sign the image.
	cosign sign "$(REGISTRY)":@$(shell crane digest $(REGISTRY):$(DOCKER_TAG))

cosign-2: ## Scan the registry.
	crane ls $(REGISTRY)

cosign-3: ## Verify the image.
	cosign verify $(REGISTRY):@$(shell crane digest $(REGISTRY):$(DOCKER_TAG))

cosign-4: ## See the signature.
	cosign verify $(REGISTRY):@$(shell crane digest $(REGISTRY):$(DOCKER_TAG)) | jless

sign-verify:
	cosign verify --certificate-identity=andrea.panisson@sparkfabrik.com --certificate-oidc-issuer="https://github.com/login/oauth" $(IMAGE):1.0.0 | jless

##@ SBOM
sbom-1: ## Generate SBOM.
	syft ${REGISTRY}:${DOCKER_TAG}

sbom-2: ## Save SBOM in CycloneDX format.
	syft ${REGISTRY}:${DOCKER_TAG} -o cyclonedx-json > sbom-cyclonedx.json

sbom-3: ## Sign SBOM.
	cosign attest --predicate sbom-cyclonedx.json --type cyclonedx $(REGISTRY):$(DOCKER_TAG)

sbom-4: ## Scan the registry.
	crane ls $(REGISTRY)

sbom-5: ## Verify sbom attestation and download the SBOM file.
	cosign verify-attestation --type cyclonedx $(REGISTRY):$(DOCKER_TAG) > sbom-attestation.json

sbom-6:	## Extract the sbom payload from the attestation.
	cat sbom-attestation.json | jq -r .payload | base64 -d | jq -r ".predicate.Data" | jless

##@ Vulnerability Scanning
vuln-1: ## Scan the image with grype.
	cat sbom-cyclonedx.json | grype

vuln-2:	## Scan the sbom downloaded from the attestation.
	cosign verify-attestation --type cyclonedx $(REGISTRY):$(DOCKER_TAG) | jq -r .payload | base64 -d | jq -r ".predicate.Data" | grype

##@ K8S
k8s-0: ## Create a kind cluster
	@kind create cluster --name cosign-demo || true

k8s-1: ## Install kyverno.
	@kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.8.5/install.yaml || true

k8s-apply-policies: k8s-2 k8s-8

k8s-2: ## Apply kyverno policy.
	kubectl apply -f k8s/kyverno/policy-check-signature.yaml

k8s-3: ## Deploy nyancat.
	kubectl apply -f k8s/deployment.yaml
	kubectl apply -f k8s/svc.yaml

k8s-4: ## Port forward to nyancat.
	pkill kubectl || true
	kubectl port-forward svc/nyancat 8080:80 &

k8s-5: ## Change the dockerfile and push a new tag without signature.
	sed -i 's/KCD2023/PHPDAY/g' src/index.html
	docker build -t $(REGISTRY):1.0.0 .
	docker push $(REGISTRY):1.0.0

k8s-6: ## Scan the registry to see pushed tags, but no signature.
	crane ls $(REGISTRY)

k8s-7: ## Sign release 1.0.0
	cosign sign "$(REGISTRY)":@$(shell crane digest $(REGISTRY):1.0.0)

k8s-8: ## Deploy a kyverno policy to enforce sbom attestation.
	kubectl apply -f k8s/kyverno/policy-check-sbom.yaml

##@ Help
.PHONY: help
help: ## Show this help screen.
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@awk 'BEGIN {FS = ":.*##";} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
