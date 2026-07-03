IMAGE        ?= strudel-local-build
DIST         ?= ./dist
NGINX_ROOT   ?= /srv/http/strudel
SAMPLES_ROOT ?= /srv/http/strudel-samples
STRUDEL_REF  ?= master

#.PHONY: build export install install-samples offline-check mirror-assets clean update tree
.PHONY: build export install install-samples mirror-assets clean update tree fetch-samples normalize-samples

## Build Docker image (builder stage)
build:
	docker compose build builder

## Export website/dist into ./dist via Docker
export:
	rm -rf $(DIST)
	mkdir -p $(DIST)
	docker compose --profile build run --rm builder

## Full pipeline: build, export, offline-check
all: build export

## Install dist to external nginx document root
install: export
	install -d $(NGINX_ROOT)
	rsync -a --delete $(DIST)/ $(NGINX_ROOT)/
	@echo "Reload nginx: sudo nginx -s reload"

## Install local sample pack to external nginx
install-samples:
	install -d $(SAMPLES_ROOT)
	rsync -a --delete ./samples/ $(SAMPLES_ROOT)/
	@echo "Reload nginx: sudo nginx -s reload"

#fetch-samples:
#	python3 scripts/fetch_samples.py ./samples $(if $(SAMPLES_PROXY),--proxy $(SAMPLES_PROXY),)

fetch-samples:
	chmod +x scripts/fetch_samples.sh
	bash scripts/fetch_samples.sh ./samples-raw

normalize-samples:
	mkdir -p ./samples-normalized
	rm -rf ./samples-raw
	find ./samples-raw -maxdepth 2 -iname "*.json" -exec cp {} ./samples-normalized/ \;
	rsync -a --exclude='.git' --exclude='*.json' ./samples-raw/ ./samples-normalized/
	mv ./samples-normalized ./samples

## Check that dist contains no external HTTP references
#offline-check:
#	./scripts/offline-check.sh $(DIST)

## Download + rewrite external URLs found in dist (fallback, prefer patches)
mirror-assets:
	./scripts/mirror-assets.sh $(DIST)

## Rebuild from latest master + re-export + check
update: build export offline-check

## Show exported tree (depth 3)
tree:
	find $(DIST) -maxdepth 3 | sort

## Start optional local nginx (profile=dev)
dev-up:
	docker compose --profile dev up -d nginx

dev-down:
	docker compose --profile dev down

dev-logs:
	docker compose --profile dev logs -f nginx

## Enter build container for debugging
shell:
	docker run --rm -it $(IMAGE) bash

clean:
	rm -rf $(DIST)
