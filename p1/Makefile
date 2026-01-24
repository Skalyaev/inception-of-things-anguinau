USERNAME=anguinau
VOLUME_DIR=volume

all: up

up:
	@mkdir -p "$(VOLUME_DIR)"
	@vagrant up --provider=virtualbox

down:
	@vagrant halt

clean:
	@-vagrant halt
	@-vagrant destroy -f
	@-rm -rf "$(VOLUME_DIR)/"*

re: clean all

ssh-server:
	@vagrant ssh "$(USERNAME)S"

ssh-worker:
	@vagrant ssh "$(USERNAME)SW"

.PHONY: all up down clean re ssh-server ssh-worker
