CLUSTER_NAME=iot

SCRIPT_DIR=script
GITLAB_DIR=$(SCRIPT_DIR)/gitlab
SETUP_SCRIPT=$(SCRIPT_DIR)/setup.sh

GITLAB_UP_SCRIPT=$(GITLAB_DIR)/up.sh
SWITCH_SCRIPT=$(GITLAB_DIR)/switch.sh

GITLAB_NAMESPACE=gitlab
GITLAB_LOCAL_URL=gitlab.local
GITLAB_INTERN_URL=gitlab-webservice-default.gitlab.svc.cluster.local:8181
GITLAB_PROJECT_URI=anguinau/inception-of-things-anguinau

APPLICATION_NAMESPACE=argocd
APPLICATION_NAME=application

ETC_HOSTS_SED_IP=/^[[:space:]]*127\.0\.0\.1[[:space:]]
ETC_HOSTS_SED_DOMAIN=\+gitlab\.local[[:space:]]*$$/d

all: up

up:
	@KUBE_CONTEXT="k3d-$(CLUSTER_NAME)" \
		GITLAB_URL="$(GITLAB_INTERN_URL)" \
		GITLAB_PROJECT="$(GITLAB_PROJECT_URI)" \
		bash "$(SETUP_SCRIPT)" "$(CLUSTER_NAME)"

	@KUBE_CONTEXT="k3d-$(CLUSTER_NAME)" \
		bash "$(GITLAB_UP_SCRIPT)" \
		"$(GITLAB_NAMESPACE)" \
		"$(GITLAB_LOCAL_URL)" \
		"$(GITLAB_PROJECT_URI)"

start:
	@k3d cluster start "$(CLUSTER_NAME)"

down:
	@k3d cluster stop "$(CLUSTER_NAME)"

clean:
	@-k3d cluster stop "$(CLUSTER_NAME)"
	@-k3d cluster delete "$(CLUSTER_NAME)"

	@-kubectl config delete-context \
		"k3d-$(CLUSTER_NAME)" 2>'/dev/null'

	@-kubectl config delete-cluster \
		"k3d-$(CLUSTER_NAME)" 2>'/dev/null'

	@-kubectl config unset \
		"users.k3d-$(CLUSTER_NAME)" 2>'/dev/null'

	@-sudo sed -i \
		"$(ETC_HOSTS_SED_IP)$(ETC_HOSTS_SED_DOMAIN)" '/etc/hosts'

re: clean up

argocd-password:
	@kubectl -n argocd get secret 'argocd-initial-admin-secret' \
		-o jsonpath='{.data.password}' | base64 -d; echo

argocd-webapp:
	@kubectl -n 'argocd' port-forward \
		'deploy/argocd-server' '9090:8080'

switch-version:
	@KUBE_CONTEXT="k3d-$(CLUSTER_NAME)" \
		bash "$(SWITCH_SCRIPT)" \
		"$(GITLAB_NAMESPACE)" \
		"$(GITLAB_LOCAL_URL)" \
		"$(GITLAB_PROJECT_URI)" \
		"$(APPLICATION_NAMESPACE)" \
		"$(APPLICATION_NAME)"

.PHONY: all up start down clean re \
	argocd-password argocd-webapp switch-version
