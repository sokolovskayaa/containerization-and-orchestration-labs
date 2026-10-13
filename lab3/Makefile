# Сборка образов shop и загрузка их в kind-кластер.
#   make images                — собрать и загрузить версию 1.0.0
#   make images VERSION=1.0.1  — новая версия (пригодится для rolling update в Части 2)
REGISTRY ?= registry.shop.local
VERSION  ?= 1.0.0
CLUSTER  ?= shop

.PHONY: images build load

images: build load

build:
	docker build -t $(REGISTRY)/api:$(VERSION) --build-arg VERSION=$(VERSION) services/api
	docker build -t $(REGISTRY)/worker:$(VERSION) --build-arg VERSION=$(VERSION) services/worker

load:
	kind load docker-image $(REGISTRY)/api:$(VERSION) $(REGISTRY)/worker:$(VERSION) --name $(CLUSTER)
