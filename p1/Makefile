USERNAME=anguinau
VOLUME_DIR=volume

all: up

up:
	@mkdir -p "$(VOLUME_DIR)"
	@vagrant up --provider=virtualbox

down:
	@vagrant halt

clean: down
	@vagrant destroy -f
	@rm -rf "$(VOLUME_DIR)/"*

re: clean up

ssh-server:
	@vagrant ssh "$(USERNAME)S"

ssh-worker:
	@vagrant ssh "$(USERNAME)SW"

.PHONY: all up down clean re ssh-server ssh-worker
