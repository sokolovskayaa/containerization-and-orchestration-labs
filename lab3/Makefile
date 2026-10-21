# Сборка образов shop и загрузка их в kind-кластер.
#   make images                — собрать и загрузить версию 1.0.0
#   make images VERSION=1.0.1  — новая версия (пригодится для rolling update в Части 2)
#   make postgres-image        — образ Postgres для CloudNativePG (Часть 3)
REGISTRY ?= registry.shop.local
VERSION  ?= 1.0.0
CLUSTER  ?= shop
PLATFORM ?= linux/arm64
# Тег должен совпадать с postgres.image.tag в chart/shop/values.yaml.
PG_TAG   ?= 18.6-system-trixie

.PHONY: images build load load-image postgres-image

images: build load

build:
	docker build -t $(REGISTRY)/api:$(VERSION) --build-arg VERSION=$(VERSION) services/api
	docker build -t $(REGISTRY)/worker:$(VERSION) --build-arg VERSION=$(VERSION) services/worker

load:
	kind load docker-image $(REGISTRY)/api:$(VERSION) $(REGISTRY)/worker:$(VERSION) --name $(CLUSTER)

# Обход ошибки kind load docker-image с multi-platform metadata.
# Пример: make load-image IMAGE="registry.shop.local/api:1.0.3 registry.shop.local/worker:1.0.0"
load-image:
	test -n "$(IMAGE)" || (echo "Usage: make load-image IMAGE=..."; exit 1)
	for node in $$(kind get nodes --name $(CLUSTER)); do \
		echo "Loading $(IMAGE) into $$node"; \
		docker save $(IMAGE) | docker exec -i $$node ctr --namespace=k8s.io images import --digests -; \
	done

# Копия официального образа в нашем реестре, иначе её не пустит политика trusted-registry.
# Загружаем через ctr без --all-platforms: kind load docker-image может искать
# digest другой платформы, которой нет в локальном Docker-хранилище.
postgres-image:
	docker pull --platform $(PLATFORM) ghcr.io/cloudnative-pg/postgresql:$(PG_TAG)
	docker tag ghcr.io/cloudnative-pg/postgresql:$(PG_TAG) $(REGISTRY)/postgresql:$(PG_TAG)
	for node in $$(kind get nodes --name $(CLUSTER)); do \
		echo "Loading $(REGISTRY)/postgresql:$(PG_TAG) into $$node"; \
		docker save $(REGISTRY)/postgresql:$(PG_TAG) | docker exec -i $$node ctr --namespace=k8s.io images import --digests -; \
	done
