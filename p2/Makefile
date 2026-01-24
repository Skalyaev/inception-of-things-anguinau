USERNAME=anguinau
VOLUME_DIR=volume

HOST_FILE=/etc/hosts

APP1_HOST=192.168.56.110 app1.com
APP2_HOST=192.168.56.110 app2.com

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

ssh:
	@vagrant ssh "$(USERNAME)S"

host:
	@echo "$(APP1_HOST)" | sudo tee -a "$(HOST_FILE)"
	@echo "$(APP2_HOST)" | sudo tee -a "$(HOST_FILE)"

.PHONY: all up down clean re ssh host
