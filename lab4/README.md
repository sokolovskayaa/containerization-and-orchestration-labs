# Лабораторная работа 4 — SLA критического пути под перегрузкой

https://github.com/KeladKaal/containerization-and-orchestration/blob/main-rus/lecture-4-scheduling-resources/lab.md

## Part 0 — batch

`services/batch` содержит минимальное Kotlin приложение для фоновой нагрузки.

Параметры приложения:

- `MEMORY_MB` — объём удерживаемой памяти;
- `CPU_WORKERS` — число потоков, выполняющих вычислительный цикл.


Приложение собрано как Kotlin/JVM-приложение. Для сборки использовалась
двухэтапная Docker-сборка: на первом этапе Gradle собирает приложение, на
втором оно запускается в образе `eclipse-temurin:25-jre` от непривилегированного
пользователя `batch`.

Образ получил явный тег:

```text
registry.shop.local/batch:0.1.0
```

![Сборка Kotlin-приложения и Docker-образа](screenshots/01-batch-build.png)

Контейнер запущен с параметрами `MEMORY_MB=128` и `CPU_WORKERS=1`. Внутри
контейнера приложение выделяет 128 MiB памяти и запускает один бесконечный
вычислительный поток.

![Потребление CPU и памяти контейнером](screenshots/02-batch-stats.png)

По данным `docker stats`, контейнер потреблял около 100% одного CPU и 180.8 MiB
памяти. Потребление памяти выше заданных 128 MiB объясняется накладными
расходами JVM и самого процесса: переменная `MEMORY_MB` задаёт размер массива,
а не полный RSS контейнера.

Логи подтверждают, что приложение запустилось с ожидаемыми параметрами и
продолжает работать:

![Логи работающего batch](screenshots/03-batch-logs.png)

## Часть 1: выбор механизма разнесения подов

Для разнесения реплик API можно использовать `podAntiAffinity` или
`topologySpreadConstraints`.

`podAntiAffinity` задаёт правило размещения относительно других подов. В
строгом режиме `requiredDuringSchedulingIgnoredDuringExecution` он запрещает
размещать подходящие поды в одном домене топологии. Если использовать в
качестве домена Kubernetes-ноду (`kubernetes.io/hostname`), то на одной ноде
может находиться не более одной реплики API.

В нашем кластере две worker-ноды и три реплики API. Поэтому строгий
`podAntiAffinity` оказался бы слишком жёстким: две реплики разместились бы на
разных нодах, а третья осталась бы в состоянии `Pending`. Мягкий режим
`preferredDuringSchedulingIgnoredDuringExecution` позволил бы запустить все
реплики, но не гарантировал бы их разнесение.

`topologySpreadConstraints` описывает не запрет соседства, а требуемое
распределение подов между доменами топологии. В нашем случае доменом является
Kubernetes-нода. Параметр `maxSkew` задаёт максимально допустимую разницу в
количестве подходящих подов между нодами, а `whenUnsatisfiable` определяет
поведение планировщика, если это условие невозможно выполнить.

Для лабы выбран механизм `topologySpreadConstraints` с распределением по
нодам и допустимым перекосом `maxSkew: 1`. При трёх репликах и двух worker-нодах
ожидается распределение `2 + 1`. При этом все реплики могут быть запущены, а
разница в количестве реплик между нодами не превышает одной.

Этот механизм выбран потому, что он лучше соответствует задаче лабы: требуется
не просто запретить совместное размещение подов, а равномерно распределить
реплики критического сервиса между доступными нодами. Такое распределение
повышает отказоустойчивость: отказ одной ноды не приводит к потере всех
реплик API.

Выбор механизма оформлен декларативно в Helm-чарте. В `values.yaml` задан
параметр `scheduling.mechanism: topologySpreadConstraints`, а шаблон API
подставляет соответствующий блок `topologySpreadConstraints` в Pod-шаблон.
Поэтому правило является частью описания приложения и воспроизводится при
каждом `helm upgrade`, а не задаётся ручным изменением уже созданного
Deployment.

## Часть 2: тесная площадка

Для эксперимента используется kind-кластер с двумя worker-нодами. Это
позволяет одновременно разместить несколько реплик критического сервиса и
создать ограничение по ресурсам для фоновой нагрузки `batch`.

Перед добавлением `batch` в Helm-чарт была сформулирована начальная гипотеза
по его ресурсам на основании наблюдения из Части 0: контейнер потреблял около
100% одного CPU и 180.8 MiB памяти.

Начальные значения:

| Ресурс | requests | limits |
|---|---:|---:|
| CPU | 100m | 1000m |
| Memory | 64Mi | 256Mi |

Лимит памяти выбран выше наблюдавшегося RSS, чтобы на первом запуске не
получить `OOMKilled` из-за слишком маленького ограничения. Requests меньше
limits намеренно: планировщик резервирует для `batch` небольшую гарантированную
долю ресурсов, а сам контейнер при наличии свободной ёмкости может потреблять
больше. Эти значения являются первоначальной гипотезой и в дальнейшем будут
сопоставлены с фактическими наблюдениями.

### Проблема при создании kind-кластера

Первая попытка создать кластер `shop` завершилась ошибкой на этапе запуска
control-plane. В логе kind API-сервер перестал отвечать:

```text
failed to create cluster
connect: connection refused
```

Диагностика показала, что Docker Desktop был ограничен примерно 4 GiB памяти.
При этом уже запущенный кластер `kind-lab2` занимал 2.452 GiB, а старый
контейнер `lab4-batch` — ещё около 183 MiB и один CPU. Создание ещё трёх
контейнеров kind привело к нехватке ресурсов во время инициализации API-сервера.

Поэтому проблема возникла до установки Helm-чарта и не была связана с
`batch` или `topologySpreadConstraints`. Для повторной попытки нужно временно
остановить старый кластер `lab2` и контейнер `lab4-batch` либо увеличить лимит
ресурсов Docker Desktop. Остановка контейнеров не удаляет кластер и позволяет
вернуть его позже.

После временной остановки `kind-lab2` и контейнера `lab4-batch` кластер
`shop` был создан успешно. В нём работают две worker-ноды, необходимые для
проверки распределения реплик API:

```text
NAME                 STATUS   ROLES           VERSION
shop-control-plane   Ready    control-plane   v1.37.0
shop-worker          Ready    <none>          v1.37.0
shop-worker2         Ready    <none>          v1.37.0
```

Текущий kubectl-контекст — `kind-shop`. Старый кластер `kind-lab2` не удалён,
а только временно остановлен для освобождения ресурсов Docker.

Состояние нод также проверено через OpenLens:

![Ноды kind-кластера shop в OpenLens](screenshots/part2-cluster-nodes.png)

### Сборка и загрузка образов

Образы API и worker были собраны с теми тегами, которые указаны в
`values.yaml`: `api:1.0.3` и `worker:1.0.0`. Образ `batch:0.1.0` был собран в
Части 0.

Первая попытка загрузить образ PostgreSQL обычной командой
`kind load docker-image` завершилась ошибкой:

```text
ctr: content digest ... not found
```

Причина связана с multi-platform metadata: kind импортировал образ через
`ctr images import --all-platforms`, хотя локально был доступен только ARM64
вариант. Для исправления образ PostgreSQL загружается в каждую ноду через
`ctr images import --digests`, без флага `--all-platforms`. После этого образ
был успешно импортирован в `shop-control-plane`, `shop-worker` и `shop-worker2`.

Остальные локальные образы были загружены тем же способом одной командой:

```text
make load-image IMAGE="registry.shop.local/api:1.0.3 registry.shop.local/worker:1.0.0 registry.shop.local/batch:0.1.0"
```

В выводе команды присутствуют последовательные этапы загрузки в каждую из
трёх нод: `shop-control-plane`, `shop-worker` и `shop-worker2`. Для всех трёх
образов (`api:1.0.3`, `worker:1.0.0`, `batch:0.1.0`) импорт завершился без
ошибок. Таким образом, все образы, необходимые для дальнейшего развёртывания
чарта, доступны на каждой ноде kind-кластера.

### Установка Kyverno

Kyverno был установлен в namespace `kyverno` через Helm-чарт версии `3.9.1`.
Поскольку первая попытка установки была остановлена во время ожидания готовности,
повторный запуск выполнил успешное обновление релиза до ревизии 2:

```text
Release "kyverno" has been upgraded. Happy Helming!
STATUS: deployed
REVISION: 2
Chart version: 3.9.1
Kyverno version: v1.19.1
```

После установки все основные компоненты Kyverno готовы:

```text
kyverno-admission-controller   1/1   Running
kyverno-background-controller  1/1   Running
kyverno-cleanup-controller     1/1   Running
kyverno-reports-controller     1/1   Running
kyverno-migrate-resources      0/1   Completed
```

Компонент `kyverno-migrate-resources` является одноразовой Job, поэтому его
статус `Completed` означает успешное завершение миграции, а не ошибку.
Helm также вывел предупреждение, что одна реплика admission-controller не
обеспечивает отказоустойчивый режим HA. Для локального учебного kind-кластера
это допустимо.

### Применение политик

После готовности Kyverno были применены пять кластерных политик:

```text
clusterpolicy.kyverno.io/disallow-latest created
clusterpolicy.kyverno.io/disallow-privileged created
clusterpolicy.kyverno.io/require-labels created
clusterpolicy.kyverno.io/require-limits created
clusterpolicy.kyverno.io/trusted-registry created
```

Проверка показала, что все политики активны для admission-проверок и готовы:

```text
NAME                  ADMISSION   BACKGROUND   READY   MESSAGE
disallow-latest       true        true         True    Ready
disallow-privileged   true        true         True    Ready
require-labels        true        true         True    Ready
require-limits        true        true         True    Ready
trusted-registry      true        true         True    Ready
```

При применении Kyverno вывел предупреждение о deprecated API
`kyverno.io/v1 ClusterPolicy`. Это предупреждение о будущем переходе на новые
типы политик, а не ошибка: текущие политики успешно созданы и имеют статус
`Ready`.

Порядок установки важен: Kyverno проверяет новые запросы к Kubernetes API на
этапе admission. Поэтому сначала устанавливаются политики, а уже затем
разворачивается приложение `shop`. Иначе некорректные Pod-ы могли бы успеть
создаться до включения проверок; установка политики не является заменой
валидации уже созданных ресурсов.

Политика `require-limits` требует, чтобы в каждом контейнере были указаны
`resources.limits.cpu` и `resources.limits.memory`. В общем случае отсутствие
лимита может привести к неконтролируемому потреблению ресурсов и `OOM`, но в
данной конфигурации такой Pod будет отклонён Kyverno ещё до запуска.

### Установка CloudNativePG

После Kyverno был установлен оператор CloudNativePG через Helm-чарт версии
`0.29.1` в namespace `cnpg-system`:

```text
Release "cnpg" does not exist. Installing it now.
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

Проверка показала, что Pod оператора готов:

```text
NAME                                   READY   STATUS    RESTARTS   AGE
cnpg-cloudnative-pg-7b5f5d7b65-2gk2x   1/1     Running   0          18s
```

Оператор добавляет в Kubernetes API ресурс `Cluster` группы
`postgresql.cnpg.io/v1`. Поэтому его установка необходима до развёртывания
PostgreSQL-ресурса из Helm-чарта `shop`.

### Первый запуск чарта и устранение проблем

При первом запуске чарта Helm не мог завершить ожидание готовности всех
ресурсов. У одной реплики API был статус `Pending`. Планировщик сообщил:

```text
1 node(s) had untolerated taint(s), 2 node(s) didn't match pod topology spread constraints
```

Причина состояла в том, что control-plane имел taint
`node-role.kubernetes.io/control-plane:NoSchedule`, но всё равно учитывался
при расчёте топологических доменов. В результате две worker-ноды не могли
разместить третью реплику при `maxSkew: 1`. Для исправления в
`topologySpreadConstraints` добавлен параметр:

```yaml
nodeTaintsPolicy: Honor
```

После этого при расчёте учитываются только подходящие ноды, и для трёх реплик
на двух worker-нодах становится допустимым распределение `2 + 1`.

Второй проблемой был Pod `batch`. Сначала он завершался с ошибкой:

```text
java.lang.OutOfMemoryError: Java heap space
```

Приложение выделяет `ByteArray` размером `128 MiB`, а стандартный максимальный
heap JVM при лимите контейнера оказался недостаточным. В чарт добавлена
переменная `JAVA_TOOL_OPTIONS`, а параметры batch скорректированы:

```yaml
MEMORY_MB: 128
JAVA_TOOL_OPTIONS: -Xmx256m
resources:
  requests:
    memory: 64Mi
  limits:
    memory: 384Mi
```

Лимит увеличен с первоначальных `256Mi` до `384Mi`, чтобы учесть heap и
нативные накладные расходы JVM, не уменьшая моделируемую нагрузку приложения.

### Итоговое развёртывание

После исправлений Helm-чарт прошёл lint-проверку и был обновлён до ревизии 4:

```text
1 chart(s) linted, 0 chart(s) failed
STATUS: deployed
REVISION: 4
DESCRIPTION: Upgrade complete
```

На момент проверки все Pod-ы находились в состоянии `Running` и были готовы:

```text
NAME                      READY   STATUS    RESTARTS   NODE
api-989df757d-58gc4       1/1     Running   0           shop-worker2
api-989df757d-7wn7n       1/1     Running   0           shop-worker
api-989df757d-phvvn       1/1     Running   0           shop-worker2
batch-6cb49bf449-bsqwr    1/1     Running   0           shop-worker2
postgres-1                1/1     Running   0           shop-worker
worker-567d7f4b66-b95zj   1/1     Running   0           shop-worker2
worker-567d7f4b66-qrnms   1/1     Running   0           shop-worker
```

Таким образом, три реплики API распределены между worker-нодами в соотношении
`2 + 1`, batch запущен с заданной фоновой нагрузкой, PostgreSQL работает через
CloudNativePG, а все ограничения Kyverno допускают итоговый набор ресурсов.

Через несколько минут после развёртывания выполнена повторная проверка. Все
Pod-ы сохранили готовность, а счётчик перезапусков остался равен нулю:

```text
NAME                      READY   STATUS    RESTARTS   NODE
api-989df757d-58gc4       1/1     Running   0           shop-worker2
api-989df757d-7wn7n       1/1     Running   0           shop-worker
api-989df757d-phvvn       1/1     Running   0           shop-worker2
batch-6cb49bf449-bsqwr    1/1     Running   0           shop-worker2
postgres-1                1/1     Running   0           shop-worker
worker-567d7f4b66-b95zj   1/1     Running   0           shop-worker2
worker-567d7f4b66-qrnms   1/1     Running   0           shop-worker
```

Состояние PostgreSQL подтверждено оператором:

```text
postgres   1   1   Cluster in healthy state   postgres-1
```

Логи batch подтверждают запуск с заданными параметрами и продолжающуюся
работу процесса:

```text
Picked up JAVA_TOOL_OPTIONS: -Xmx256m
batch started: memoryMb=128, cpuWorkers=1
batch is still running
```

Финальное состояние приложения также проверено визуально в OpenLens:

![Финальное состояние Pod-ов namespace shop в OpenLens](screenshots/final-shop-pods-openlens.png)

### Подготовка мониторинга для Части 3

Для получения реальных рекомендаций ресурсов нужен Prometheus-стек в том же
кластере `kind-shop`, где работает namespace `shop`. Prometheus из другого
кластера не может собирать метрики этих Pod-ов.

Перед установкой мониторинга в политики `require-labels`, `require-limits` и
`trusted-registry` добавлен namespace `monitoring` в список инфраструктурных
исключений. Это не ослабляет проверки для приложения в namespace `shop`.
Политики `disallow-latest` и `disallow-privileged` продолжают применяться к
ресурсам мониторинга.

После обновления политик все пять ClusterPolicy имеют статус `Ready`:

```text
disallow-latest       true   true   True   Ready
disallow-privileged   true   true   True   Ready
require-labels        true   true   True   Ready
require-limits        true   true   True   Ready
trusted-registry      true   true   True   Ready
```

### Установка Prometheus-стека

Для Части 3 мониторинг установлен в тот же кластер `kind-shop`, где находится
приложение `shop`. Использован Helm-релиз `monitoring` чарта
`kube-prometheus-stack` в namespace `monitoring`.

После завершения установки все основные компоненты готовы:

```text
alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2   Running
monitoring-grafana                                       3/3   Running
monitoring-kube-prometheus-operator                      1/1   Running
monitoring-kube-state-metrics                             1/1   Running
monitoring-prometheus-node-exporter                       1/1   Running
prometheus-monitoring-kube-prometheus-prometheus-0       2/2   Running
```

Prometheus и связанные компоненты устанавливаются в отдельный namespace
`monitoring`, а `ServiceMonitor` приложения будет добавлен в Helm-чарт `shop`.

После добавления шаблона `ServiceMonitor` Helm-релиз `shop` обновлён до
ревизии 5:

```text
STATUS: deployed
REVISION: 5
DESCRIPTION: Upgrade complete
```

Проверка Kubernetes-ресурса показала, что мониторинг API создан:

```text
NAME   AGE
api    5s
```

Объект собирает метрики сервиса `api` через именованный порт `http`, endpoint
`/metrics` и интервалом `15s`.

Работа `ServiceMonitor` проверена в интерфейсе Prometheus. Target
`serviceMonitor/shop/api/0` обнаружил все три реплики API, и каждый endpoint
`/metrics` имеет состояние `UP`:

![Prometheus видит все реплики API](screenshots/prometheus-api-targets-up.png)

### Нагрузочный тест для Части 3

Для создания реальной нагрузки был использован сценарий k6
`lab4/load/order-load.js`. Через локальный port-forward он отправлял запросы
`POST /order`, то есть проходил полный путь `api → postgres`.

Параметры сценария: 5 виртуальных пользователей и 3 минуты работы. Результат:

```text
checks_total.......: 3669
checks_succeeded...: 100.00%
checks_failed......: 0.00%
http_req_failed....: 0.00%
http_reqs..........: 3669   20.359069/s
http_req_duration..: avg=44.3ms  p(90)=101.91ms  p(95)=129.01ms  max=230.59ms
```

Все 3669 заказов были успешно созданы. Полученные метрики будут использованы
`krr` для рекомендации значений `requests` и `limits` критического пути.


## Часть 5 — приоритеты, QoS и PDB

[Итоговый отчёт](PART5.md). Проверено в **shop-lab4 на двух нодах**:
Helm shop revision 3 deployed, все поды Ready. API и PostgreSQL — Guaranteed
с приоритетом 100000, batch — Burstable с приоритетом -1000; PDB действуют.

KRR с [адаптером обнаружения CNPG](krr-cnpg/README.md) получил числовые
рекомендации PostgreSQL. Память базы — 137Mi. CPU-пороги обоснованы проверками
запуска и нагрузки и явно заданы в KRR. Итоговые значения в
values-part5-final.yaml сгенерированы из сохранённых JSON-отчётов.
Короткая итоговая проверка: **300/300 заказов, 0 ошибок, p95=31.25ms**.
История KRR ограничена; проверку не следует считать доказательством SLA
под дефицитом ресурсов. Preemption и eviction пока не проводились.

Старый shop сохранён и остановлен; текущий контекст — kind-shop-lab4.

### Batch: сборка и включение

Добавлен Deployment с низким приоритетом и Burstable (requests 100m/256Mi,
limits 1000m/512Mi). Параметры MEMORY_MB и CPU_WORKERS задаются через values.
Альтернативный Dockerfile.standalone собирает Java-реализацию через javac,
без зависимостей Gradle/Kotlin; исходная Kotlin-реализация сохранена.
Сборка standalone подтверждена предоставленным пользователем логом Docker,
импорт в kind и запуск batch проверены: под Ready, QoS Burstable.

```bash
docker build -f lab4/services/batch/Dockerfile.standalone -t registry.shop.local/batch:0.1.0 lab4/services/batch
kind load docker-image registry.shop.local/batch:0.1.0 --name shop
helm upgrade shop lab3/chart/shop -n shop -f lab4/values-part5-final.yaml --wait --timeout 3m
```

Автоматизированный вариант для context kind-shop:
`bash lab4/scripts/finish-part5.sh`. Он включает batch дополнительным values-файлом.
