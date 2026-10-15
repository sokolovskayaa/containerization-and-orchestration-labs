# Сборка образов shop и загрузка их в kind-кластер.
#   make images                — собрать и загрузить версию 1.0.0
#   make images VERSION=1.0.1  — новая версия (пригодится для rolling update в Части 2)
#   make postgres-image        — образ Postgres для CloudNativePG (Часть 3)
REGISTRY ?= registry.shop.local
VERSION  ?= 1.0.0
CLUSTER  ?= shop
# Тег должен совпадать с postgres.image.tag в chart/shop/values.yaml.
PG_TAG   ?= 18.6-system-trixie

.PHONY: images build load postgres-image

images: build load

build:
	docker build -t $(REGISTRY)/api:$(VERSION) --build-arg VERSION=$(VERSION) services/api
	docker build -t $(REGISTRY)/worker:$(VERSION) --build-arg VERSION=$(VERSION) services/worker

load:
	kind load docker-image $(REGISTRY)/api:$(VERSION) $(REGISTRY)/worker:$(VERSION) --name $(CLUSTER)

# Копия официального образа в нашем реестре, иначе её не пустит политика trusted-registry.
# Пересборка через FROM даёт образ под одну платформу: мультиархитектурный kind load не загружает
# (ошибка "content digest ... not found").
postgres-image:
	echo "FROM ghcr.io/cloudnative-pg/postgresql:$(PG_TAG)" | docker build -t $(REGISTRY)/postgresql:$(PG_TAG) -
	kind load docker-image $(REGISTRY)/postgresql:$(PG_TAG) --name $(CLUSTER)
