# Лаба 3: платформа для shop

https://github.com/KeladKaal/containerization-and-orchestration/blob/main-rus/lecture-3-kubernetes-control-plane/lab.md

Кластер: kind `shop` (1 control-plane + 2 worker), конфиг в `kind-config.yaml`.
Образы: `make images` собирает `api`/`worker` и загружает их в ноды.

## Как развернуть с нуля

Нужны Docker, kind, helm и kubectl. Все команды выполняются из папки `lab3/`.

1. Кластер:
   ```bash
   kind create cluster --config kind-config.yaml
   ```
2. Образы `api` и `worker` (в `values.yaml` у api тег `1.0.3`, у worker `1.0.0`):
   ```bash
   make images
   make images VERSION=1.0.3
   ```
3. Образ Postgres в нашем реестре (иначе его не пустит `trusted-registry`):
   ```bash
   make postgres-image
   ```
4. Kyverno и политики:
   ```bash
   helm repo add kyverno https://kyverno.github.io/kyverno/
   helm install kyverno kyverno/kyverno -n kyverno --create-namespace --version 3.9.1 --wait
   kubectl apply -f policies/
   ```
5. Оператор CloudNativePG:
   ```bash
   helm repo add cnpg https://cloudnative-pg.github.io/charts
   helm install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace --version 0.29.1 --wait
   ```
6. Чарт `shop` (api, worker, postgres):
   ```bash
   helm upgrade --install shop chart/shop -n shop --create-namespace
   ```
7. Проверка: все поды `1/1`, кластер Postgres в `Cluster in healthy state`:
   ```bash
   kubectl get pods -n shop
   kubectl get cluster -n shop
   ```

Порядок важен: политики ставятся раньше чарта, а оператор раньше объекта `Cluster` (иначе API-сервер не знает такого типа).

## Часть 1: Ограждения на кластер

### Выбор движка

Я никогда не работал с k8s :), поэтому по совету великой нейронки я использовал kyverno. Как я понял, в Gatekeeper пишут на языке Rego, и я подумал, зачем мне его в лишний раз смотреть, когда я могу взять движок kyverno и писать политики на YAML, на котором пишутся манифесты под объекты k8s.

Установили kyverno через helm, а helm через brew ( macOS пакетный менеджер )

делаем `kubectl get pods -n kyverno`

![Поды Kyverno запущены](screenshots/kyverno_install.png)

### Правила

Применяем наши политики

![Применение политик](screenshots/policies_apply.png)

Видно, что все наши политики работают

![Политики в статусе Ready](screenshots/policies_ready.png)

Политики лежат в `policies/`.

Главное называть их по-разному :), а то, если мы назовем их одинаково, api-server просто перезапишет существующую в etcd.

В политике есть два главных поля: 

`rules` - куда мы пишем правила
Ну и внутри правил у нас `validate`, который как раз проверяет наши манифесты на входе.

`failureAction` - сразу отклоняет объект, если он плохой ( Enforce ) или пропускает, но записывает ( Audit )
`message` - то, что возвращается при плохом манифесте, который не прошел `pattern` валидации
`pattern` - как раз смотрит то, как наш объект должен выглядеть

`trusted-registry.yaml` политика проверяет образы на скачивания с нашего регистра, а не с внешнего ( напр. docker Hub ) - просто сравнивания название образов "registry.shop.local/" + любые символы


```yaml
pattern:                    
    spec:
        containers:
        - image: "registry.shop.local/*"

```

`require-limits.yaml` политика проверяет лимиты на наши поды - "?*" говорит о том, что memory, cpu обязан указываться хоть какой-то ( напр. "128Mi" и "250m" соотвественно )

```yaml
containers:
- resources:
    limits:
        memory: "?*"
        cpu: "?*"   
```

`disallow-latest.yaml` моя собственная политика проверяет версию на `latest` - там два правила, которые проверяют на два варианта:

1) если поставили "образ:latest", то `image: "!*:latest"` это явно запретит

```yaml                  
pattern:                  
    spec:
        containers:
        - image: "!*:latest"       
```

2) ну и чтобы не подставился по умолчанию без конкретной версии добавляем еще и `image: "*:*"`, чтобы при добавлении контейнера указывали конкретную версию

```yaml
pattern:                   
    spec:
        containers:
        - image: "*:*"        
```

`disallow-privileged.yaml` политика запрещает как-то стучаться во внешний мир ноды ( напр. через root монтировать диск ноды к нашему контейнеру и видеть содержимое соседних подов ) 

Поскольку privileged по default всегда false, можно просто проверить, чтобы это поле никогда не было true

`=(field): value` говорит, что если поле есть оно обязано быть значением  `value`, если нет такого поля, то пропускаем ( потому что по default privileged = false )

```yaml
pattern:                    
    spec:
        containers:
        - =(securityContext):
            =(privileged): false 
```

`require-labels.yaml` политика проверяющая есть ли лейблы.

```yaml
pattern:                    
    metadata:
        labels:
            app: "?*"
```

### Проверка политик

Манифесты лежат в `bad-manifests/`.

`00-good.yaml` нужен, чтобы проверить не запрещают ли политики то, что не должны запрещать. Он проходит все правила.

![00-good проходит все правила](screenshots/good_test.png)

`01-foreign-image.yaml` имеет внешний образ `image: nginx:1.27` ( не с нашего регистра ) 

![01-foreign-image отклонён trusted-registry](screenshots/foreign_image_test.png)

`02-no-limits.yaml` не имеет лимитов

![02-no-limits отклонён require-limits](screenshots/no_limits_test.png)

`03-no-labels.yaml` нет лейблов

![03-no-labels отклонён require-labels](screenshots/no_labels_test.png)

`04-privileged.yaml` ставит явно `privileged: true`, чтобы проверить работает ли запрет

![04-privileged отклонён disallow-privileged](screenshots/privileged_test.png)

`05-latest.yaml` явно указывает latest версию `image: registry.shop.local/api:latest` 

![05-latest отклонён disallow-latest](screenshots/latest_test.png)

### ПОДВОДЯ ИТОГИ 1 ГЛАВЫ

В чем проблема kyverno (скажем так): 

наверное, в том что он выставляет failurePolicy: Fail по умолчанию - короче, это значит, что если kyverno упал, то он не пропустит ни один манифест, пока его не поднять. 

С одной стороны это круто конечно, но с другой получается, что пока не поднять kyverno, процесс разработки просто встает :(, причем даже replicaset не может создать замену упавшему поду ( потому что она делает kubectl apply под капотом, а kyverno validation работает после RBAC при api-server )

ну и там  `allowExistingViolations` по умолчанию уже существующие поды, которые были добавлены до политики, просто игнорирует, и они живут и их видно в policyreport

![Старые объекты без лимитов в policyreport](screenshots/old_objects_k8s.png)

Эти объекты создали до появления политик. Kyverno их пропустил и не убил, но записал в отчёт

Но это сделано для, например, ночной загрузки (когда надо заскейлить реплики)

## Часть 2: Чарт api и worker

Чарт лежит в `chart/shop/`.

### Что в чарте

_✍️ Напиши: какие файлы в чарте и зачем каждый (Chart.yaml, values.yaml, 4 шаблона). Что вынесено в values (replicas, image, limits, healthFail) и зачем. Что заложено в шаблоны под правила Части 1 (реестр, тег, limits, метка app)._

### Установка: Kyverno не пускает плохой чарт

![Kyverno отклонил чарт с чужим образом](screenshots/helm_kyverno_denied.png)

_✍️ Напиши: что подменили через `--set` и что ответил Kyverno. Кто кого спросил: Helm → API-сервер → Kyverno._

Чистая установка:

![helm upgrade --install](screenshots/helm_install.png)

![Всё поднялось: api 3/3, worker 2/2](screenshots/chart_installed.png)

### Пробы

_✍️ Напиши: чем readiness отличается от liveness, что делает каждая при провале, кто их выполняет (kubelet)._

### Reconciliation: удалил под

![Удаляем под](screenshots/pod_delete.png)

![Под вернулся](screenshots/pod_recreated.png)

_✍️ Напиши: кто вернул под (какой контроллер) и почему у нового пода другое имя._

### Reconciliation: replicas в values

![replicas: 5 в values.yaml](screenshots/values_replicas5.png)

![helm upgrade, ReplicaSet DESIRED 5](screenshots/helm_upgrade_replicas.png)

![Появились 2 новых пода](screenshots/scale_pods.png)

_✍️ Напиши: почему ReplicaSet остался тот же (где лежит replicas). Цепочка от helm upgrade до пода._

### Ручной kubectl scale и конфликт с Helm

```
Error: UPGRADE FAILED: conflict occurred while applying object shop/api apps/v1, Kind=Deployment:
Apply failed with 1 conflict: conflict with "kubectl" with subresource "scale" using apps/v1: .spec.replicas
```

_✍️ Напиши: почему Helm не вернул 5 реплик сам. Почему следующий upgrade упал (владельцы полей, Update против Apply). Что делает `--force-conflicts`._

### Rolling update: первая попытка

![ReplicaSet-ы во время rolling update: начало](screenshots/rolling_rs_1.png)

![ReplicaSet-ы во время rolling update: конец](screenshots/rolling_rs_2.png)

![Переключение 1.0.0 → 1.0.1](screenshots/rolling_switch.png)

![Ошибки во время rolling update, fail=6](screenshots/rolling_fail.png)

_✍️ Напиши: почему поды менялись по одному (maxSurge/maxUnavailable). Откуда взялись 6 ошибок (SIGTERM против обновления EndpointSlice/kube-proxy)._

### Rolling update: после preStop

![ReplicaSet-ы: 1.0.2 → 1.0.3](screenshots/rolling_ok_rs.png)

![Обе версии отвечают вперемешку, fail=0](screenshots/rolling_ok_load.png)

![Итог: fail=0](screenshots/rolling_ok_total.png)

_✍️ Напиши: что делает `preStop: sleep 5` и почему первый upgrade с preStop ещё не защищал._

### Сломанная версия и rollback

![Новый под 0/1, рестарты, CrashLoopBackOff](screenshots/broken_pods.png)

![События пода: readiness и liveness 503](screenshots/broken_events.png)

![Нагрузка: отвечают только старые поды, fail=0](screenshots/broken_load.png)

![rollout завис, а Helm пишет deployed](screenshots/broken_rollout_stuck.png)

![helm rollback](screenshots/rollback.png)

_✍️ Напиши: почему rollout завис и сервис при этом работал (Ready → deployment-controller и EndpointSlice). Почему Helm пишет `deployed`. Почему rollback не пересоздал поды._

### Итоги Части 2

_✍️ Напиши 2–3 вывода: Helm не следит за кластером (drift), во время rolling update работают две версии сразу, без `--wait` Helm не знает, работает ли приложение._

## Часть 3: Postgres через оператора

### Выбор оператора

_✍️ Напиши: почему CloudNativePG, а не Zalando. Что такое оператор: CRD (новый тип `Cluster`) + контроллер (под, который следит за этим типом). Зачем он, если Postgres можно запустить StatefulSet-ом (failover, репликация, бэкапы, пароли)._

### Установка оператора и Kyverno

Первая попытка установить оператор:

```
Error: server-side apply failed for object cnpg-system/cnpg-cloudnative-pg apps/v1, Kind=Deployment:
admission webhook "validate.kyverno.svc-fail" denied the request:
require-labels:   autogen-only-shop-labels   ... /spec/template/metadata/labels/app/
require-limits:   autogen-only-shop-limits   ... /spec/template/spec/containers/0/resources/limits/
trusted-registry: autogen-only-shop-registry ... /spec/template/spec/containers/0/image/
```

Когда Postgres попросил диск, Kyverno заблокировал служебный под провижинера дисков kind:

```
failed to provision volume with StorageClass "standard":
resource Pod/local-path-storage/helper-pod-create-pvc-... was blocked due to the following policies
require-labels, require-limits, trusted-registry
```

_✍️ Напиши: почему исключили `cnpg-system` и `local-path-storage` только из трёх политик, а не из пяти (privileged и latest продолжают действовать). Чем это лучше, чем подгонять оператор под правила._

### Postgres в чарте

_✍️ Напиши: что в шаблоне `postgres-cluster.yaml` и как Postgres проходит все пять политик без исключений (образ скопирован в `registry.shop.local`, limits, метка `app` через `inheritedMetadata`). Почему пришлось пересобрать образ через `FROM` для `kind load`._

![Под postgres-1 и его диск](screenshots/pg_pods_pvc.png)

### api и worker работают с базой

_✍️ Напиши: откуда api и worker берут `DATABASE_URL` (Secret `postgres-app`, который создал оператор, `secretKeyRef`). Почему пароля нет ни в чарте, ни в git._

![POST /order: заказ создан](screenshots/pg_order_create.png)

![GET /orders: worker обработал заказ](screenshots/pg_orders_processed.png)

### Reconciliation: удалил под Postgres

![Под postgres-1 удалён и вернулся с тем же именем](screenshots/pg_pod_recreated.png)

![Хозяин пода — Cluster, заказ на месте](screenshots/pg_after_delete.png)

_✍️ Напиши: кто вернул под (оператор, хозяин `Cluster`, ReplicaSet нет). Почему имя то же (`postgres-1` ↔ PVC `postgres-1`). Почему заказ пережил удаление._

### spec и status

![spec объекта Cluster (1)](screenshots/pg_cluster_spec_1.png)

![spec объекта Cluster (2)](screenshots/pg_cluster_spec_2.png)

![status объекта Cluster (1)](screenshots/pg_cluster_status_1.png)

![status объекта Cluster (2)](screenshots/pg_cluster_status_2.png)

_✍️ Напиши: что в `spec` (желаемое, пишем мы, плюс значения по умолчанию от оператора) и что в `status` (фактическое, пишет оператор: `phase`, `currentPrimary`, `readyInstances`)._

### Оператор против controller-manager

_✍️ Напиши: где работает каждый (kube-system и часть Kubernetes против обычного пода в cnpg-system, поставленного нами). За чем следит (встроенные Deployment/ReplicaSet против нового типа `Cluster`). Что общего (один и тот же цикл: watch → сравнить spec с реальностью → исправить → записать status). Что оператор знает про Postgres такого, чего не знает ReplicaSet._

## Часть 4: Падение control plane

## Часть 5: Мониторинг
