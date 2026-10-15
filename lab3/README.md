# Лаба 3: платформа для shop

https://github.com/KeladKaal/containerization-and-orchestration/blob/main-rus/lecture-3-kubernetes-control-plane/lab.md

Кратенькое содержимое:

Кластер: kind `shop` (1 control-plane + 2 worker), конфиг в `kind-config.yaml`.
Образы: `make images` собирает `api`/`worker` и загружает их в ноды.

## Кратенькая сборочка

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

На этом мои мучения только начинались. Если я думал, что понимаю как работает кубер - я ошибался

Чарт лежит в `chart/shop/`.

### Что в чарте

Удивительная штука под названию Helm из под капота, делает за нас довольно много рутины. 

Коротко, из чего состоит чарт:

`Chart.yaml` там метаданные чарта, имя и версия

`values.yaml` там сидят значения, которые меняем: api.replicas: 3

И еще у нас есть удивительная папка под названием `/templates` и туда мы помещаем все YAML-манифесты,  только изменяемые значения в них заменены на подстановки

Идея, в том чтобы писать наши изменяемые значения один раз в 
`values.yaml` и уже в каждый шаблон, кое требует это значение
подставлять `{{ .Values.field... }}` и Helm при upgrate,install просто возьмет
подставит в наши шаблоны наши значение и напрямую отправит их API-Server

Но помимо этого он умеет еще и откатывать версии.

Каждый install и каждый upgrade Helm записывает как ревизию 
и хранит её прямо в кластере

типо того:

`sh.helm.release.v1.shop.v1, ...v2`


### Установка: Kyverno не пускает плохой чарт

![Kyverno отклонил чарт с чужим образом](screenshots/helm_kyverno_denied.png)

После того, как Kyverno был поставлен на стражу порядка в API-Server
из-за того, что стоят 5 политик, и cloudNativePG при установке не удовлетворял 3 из них
его пришлось исключить через namespace в этих политиках,
а потом еще и перенести образ Postgres в мой реестр. 

```YAML
exclude:
  any:
  - resources:
      namespaces: ["cnpg-system", "local-path-storage"]
```

Ну и затем, все поднялось и начало работать

![helm upgrade --install](screenshots/helm_install.png)

![Всё поднялось: api 3/3, worker 2/2](screenshots/chart_installed.png)

### Пробы

Я проверил развёрнутый чарт через helm get manifest: вписал их в Deployment 

`kubectl describe pod -n shop -l app=api | grep -E "Liveness|Readiness"`

![Пробы на подах api](screenshots/probes_describe.png)

Пробы работают в сценарии со сломанной версией. При HEALTH_FAIL=true новые поды не
проходят readiness, поэтому rollout зависает, а старые поды не удаляются.
Этот сценарий описывается в разделе про rollback.

### Reconciliation: удалил под

далее тестил то, как работает удаление пода

попробовал удалить под в replicaset

![Удаляем под](screenshots/pod_delete.png)

Параллельно в другом окне запустил 

`kubectl get pods -n shop -w`

И он тут же создал новый
Replicaset-controller (часть controller-manager)
тут же увидела, что их стало на один меньше
и желаемый результат не совпадает с фактическим
Поэтому отправила запрос на создание новой поды API-Server с префиксом
имени (имя + хеш содержимого (`template:` + непоставленные поля))
хвост API-Server сгерировал сам, записал в таблицу etcd
и затем уже Scheduler выбирал ноду для пода, и kubelet запустил наш новый под

![Под вернулся](screenshots/pod_recreated.png)

### Reconciliation: replicas в values

Дальше шел экспримент скейлинга наших подов и я стокнулся с тем, что оказывается
изменяя replicas новый replicaset (это только потом я уже понял что новая replicaset
создается ток при изменении template или при явном rollout restart - к слову
эта делает довольно простую но не очевидную вещь, дописывая в template
аннотацию `kubectl.kubernetes.io/restartedAt: <время>`) 


![replicas: 5 в values.yaml](screenshots/values_replicas5.png)

Далее мы через helm посылаем API-Server запрос на
изменённый Deployment с spec.replicas: 5

![helm upgrade, ReplicaSet DESIRED 5](screenshots/helm_upgrade_replicas.png)

Таким образом, при изменениии Deployment:

deployment-controller следит за Deployment
когда в Deployment меняется replicas, 
он меняет replicas в ReplicaSet api-7bc878dcff с 3 на 5.

Дальше replicaset-controller, смотрит 
на то сколько реплик мы хотим получить и создаёт через API-сервер
2 объекта Pod. У этих подов ещё не указана нода, поле nodeName пустое.

Дальше уже подписанный schuduler смотрит какие ноды дать под поды

и наш kubelet просто запускает наши поды и приводит их в Ready

![Появились 2 новых пода](screenshots/scale_pods.png)

### Ручной kubectl scale и конфликт с Helm

Дальше кстати было интереснее, ведь возник конфликт с kubectl
Я попытался увеличить число реплик через консольную утилиту кубера, и в след раз
сделал изменение снова через helm upgrade, но мне отказали с ошибкой

```
Error: UPGRADE FAILED: conflict occurred while applying object shop/api apps/v1, Kind=Deployment:
Apply failed with 1 conflict: conflict with "kubectl" with subresource "scale" using apps/v1: .spec.replicas
```
Как я понял, когда Helm посылает API-Server он еще и следит за тем, 
кто владеет каждым отдельным полем.

Грубо говоря

Helm upgrade делает операцию Apply и он становится владельцем Helm
Дальше, kubectl scale делает операцию Update. И так работает, 
что при Update он ничего не проверяет и просто приписывает владение себе
Еще раз Helm upgrade делает операцию Apply и мы ловим ошибку, потому что у нас
нет прав менять поле, которое закреплено под другим владельцем

Поэтому пришлось сделать --force-conflicts, чтобы он не проверял владельца

### Rolling update: первая попытка

После этого поднял версию образа api с 1.0.0 до 1.0.1 в values.yaml 
и сделал helm upgrade, параллельно долбя /health в цикле.
Поменялся template, поэтому появился новый ReplicaSet api-67d654f8c5, 
и поды заменялись на новую версию по одному (RollingUpdate), а не все сразу.

![ReplicaSet-ы во время rolling update: начало](screenshots/rolling_rs_1.png)

![ReplicaSet-ы во время rolling update: конец](screenshots/rolling_rs_2.png)

![Переключение 1.0.0 → 1.0.1](screenshots/rolling_switch.png)

![Ошибки во время rolling update, fail=6](screenshots/rolling_fail.png)

У Deployment есть два поля

maxSurge: 25%         сколько подов можно создать сверх replicas

сколько подов можно создать сверх 3. 0,75 округляется вверх, получается 1.
Значит, одновременно может существовать максимум 3 + 1 = 4 пода.

maxUnavailable: 25%   сколько подов может быть не Ready

0,75 округляется вниз, получается 0. 
Значит, Ready всегда должно быть минимум 3 − 0 = 3 пода.

### Rolling update: после preStop

Дальше я попробовал такую штуку как preStop

Идея в том, чтоб повесить перед удалением пода какие-то действия

sleep - kubelet просто ждёт заданное время.
exec — любая команда внутри контейнера.
httpGet — HTTP-запрос.

Я повесил sleep 5 seconds

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

Снова по совету великой нейронки я взял CloudNativePG, и стал разбираться с тем, как он работает
Во-первых, этот оператор-программа, по факту делающая работу контроллера,
работает с определенным типом CRD новый тип `Cluster` и контроллер, как раз следит ток за этим типом
И когда мы создаем объект Cluster наш CloudNativePG-pod подписан на наш API-Server и если таблица 
Cluster была изменена, то CloudNativePG будет с ней работать

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
