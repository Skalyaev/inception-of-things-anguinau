CLUSTER=iot

SCRIPT_DIR=script
SETUP_SCRIPT=$(SCRIPT_DIR)/setup.sh

all: up

up:
	@bash "$(SETUP_SCRIPT)" "$(CLUSTER)"

start:
	@k3d cluster start "$(CLUSTER)"

down:
	@k3d cluster stop "$(CLUSTER)"

clean:
	@-k3d cluster stop "$(CLUSTER)"
	@-k3d cluster delete "$(CLUSTER)"

	@-kubectl config delete-context "k3d-$(CLUSTER)" 2>'/dev/null'
	@-kubectl config delete-cluster "k3d-$(CLUSTER)" 2>'/dev/null'
	@-kubectl config unset "users.k3d-$(CLUSTER)" 2>'/dev/null'

re: clean all

argocd-password:
	@kubectl -n 'argocd' get secret 'argocd-initial-admin-secret' \
		-o jsonpath="{.data.password}" | base64 -d; echo

argocd-webapp:
	@kubectl -n 'argocd' port-forward 'svc/argocd-server' '8080:443'

.PHONY: all up start down clean re argocd-password argocd-webapp
