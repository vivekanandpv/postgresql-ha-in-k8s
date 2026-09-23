.PHONY: up build chaos-install deploy status watch demo-kill-leader demo-kill-follower demo-partition down

up:
	./scripts/00-create-cluster.sh

build:
	./scripts/01-build-and-load-image.sh

chaos-install:
	./scripts/02-install-chaos-mesh.sh

deploy:
	./scripts/03-deploy.sh

status:
	./scripts/status.sh

watch:
	./scripts/watch-heartbeat.sh

demo-kill-leader:
	./scripts/demo-kill-leader.sh

demo-kill-follower:
	./scripts/demo-kill-follower.sh

demo-partition:
	./scripts/demo-network-partition.sh

down:
	./scripts/teardown.sh
