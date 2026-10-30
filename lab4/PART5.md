# Часть 5 — приоритеты и гарантии ресурсов

## Что настроено и проверено

В Helm-чарт shop добавлены два PriorityClass и PodDisruptionBudget для API
и PostgreSQL. Параметры передаются через values; разовые kubectl-патчи
для настройки ресурсов не использовались.

Проверка проведена 31 октября 2026 после `helm upgrade`, релиз shop,
namespace shop, ревизия 36, статус **deployed**. Все три текущие реплики API,
PostgreSQL, batch и оба worker имеют Ready=true.

| Сервис | CPU request / limit | Memory request / limit | Фактический QoS | Приоритет |
|---|---|---|---|---|
| api (3 реплики) | 100m / 100m | 100Mi / 100Mi | Guaranteed | 100000 |
| postgres | 250m / 250m | 512Mi / 512Mi | Guaranteed | 100000 |
| batch | 100m / 1000m | 256Mi / 512Mi | Burstable | -1000 |
| worker (2 реплики) | 10m / 250m | 100Mi / 100Mi | Burstable | 0 |

Имена PriorityClass: shop-shop-critical и shop-shop-batch (имя namespace и
релиза входит в имя, потому что PriorityClass действует на весь кластер).
У критического класса PreemptLowerPriority. У batch — Never: он сам не
вытесняет чужие поды, но может быть вытеснен более приоритетным подом.

## Рекомендации krr и проверка корректировок

KRR 1.28.0 при окне 1 час и шаге 15 секунд рекомендовал API и worker
CPU request=10m, memory request=limit=100Mi, CPU limit=unset. История неполная,
успешный исходный прогон занимал только пять минут; 10m и 100Mi совпали
с минимальными порогами инструмента.

В первом варианте API получил request=limit=10m ради Guaranteed. Холодный
старт не укладывался в окно liveness-пробы: kubelet перезапускал контейнер.
Добавлена startup-проба до 120 секунд, timeout проб увеличен до 2 секунд.
После этого под стартовал, но при нагрузке в логах появились таймауты
подключения к PostgreSQL. В cgroup CPU-статистике 593 из 603 периодов были
ограничены по CPU. Локальный port-forward также оборвался, поэтому итог
этого прогона нельзя целиком приписать приложению.

Рабочий CPU-бюджет API увеличен до 100m, requests и limits оставлены равными.
Это **корректировка после проверки, а не исходная рекомендация krr**. Значение
не доказано минимально достаточным. Память 100Mi сохранена по отчёту krr.
У worker оставлен конечный CPU limit=250m по требованию обязательных лимитов.

PostgreSQL в отчёт krr не попал из-за ограничения обнаружения подов CNPG.
Его прежний бюджет 250m/512Mi сохранён. Следовательно, требование получить
числа критического пути целиком из krr пока выполнено не полностью.

## Почему batch больше не падает

В предоставленном логе первоначальный batch завершался с
`OutOfMemoryError: Java heap space`: при лимите контейнера 512Mi стандартный
heap JVM оказался слишком мал для массива 128Mi и служебных объектов.
Через values задан `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=70.0`.
Batch запустился с MEMORY_MB=128, CPU_WORKERS=1 и на момент проверки имел
ноль перезапусков. Увеличение MEMORY_MB в части 7 потребует отдельно учитывать
лимит heap и контейнера, чтобы не спутать Java heap OOM с node-pressure eviction.

Используется standalone Java-сборка без Maven/Gradle-зависимостей. Исходная
Kotlin-реализация сохранена. Изменение реализации вспомогательной нагрузки
не меняет механизм Kubernetes, который исследуется в работе.

## PDB и границы защиты

Для API задан minAvailable=1; при трёх здоровых репликах disruptionsAllowed=2.
Для PostgreSQL minAvailable=1 выбирает primary по меткам CNPG;
disruptionsAllowed=0. Автоматические PDB оператора отключены через
spec.enablePDB=false, чтобы не создавать пересекающиеся бюджеты.

PDB ограничивает добровольные выселения через Eviction API, например drain.
Он не предотвращает отказ ноды и не защищает от node-pressure eviction.
При preemption планировщик старается учитывать PDB, но не гарантирует его
соблюдение. Единственная реплика PostgreSQL с PDB не становится резервированной.

QoS и scheduler priority решают разные задачи. Guaranteed требует равных
CPU/memory requests и limits для всех контейнеров пода. Он не даёт иммунитета
к preemption. При node-pressure eviction учитываются превышение requests,
приоритет и относительное потребление ресурса: утверждение «любой Burstable
всегда удаляется раньше любого Guaranteed» было бы слишком упрощённым.

## Проверка заказов после изменения ресурсов

После успешного Helm upgrade выполнен дополнительный 30-секундный прогон
из существующего worker-пода через Service `api.shop.svc.cluster.local`,
без локального port-forward. Стандартный Python-клиент отправлял 5 POST /order
в секунду: **150 запросов, 150 ответов 201, 0 ошибок, p95=52.78ms**.
Это короткая проверка работоспособности с одной репликой batch, а не
доказательство SLA под дефицитом ресурсов из части 8.

## Доказательства и воспроизведение

- [QoS, ресурсы и приоритеты](evidence/part5-qos-resources.txt).
- [PriorityClass, PDB, PostgreSQL и Helm](evidence/part5-pdb-priority.txt).
- [Результат проверки заказов через Service](evidence/part5-service-load.json).
- [Исходные рекомендации krr](evidence/krr/after-load-report.txt).
- [CPU throttling при 10m](evidence/part5-debug/api-cpu-10m.txt).

Применение с уже загруженным образом batch:

```bash
helm upgrade shop lab3/chart/shop -n shop -f lab4/values-part5-krr.yaml -f lab4/values-batch.yaml --wait --timeout 5m
bash lab4/scripts/show-part5.sh qos
bash lab4/scripts/show-part5.sh pdb
```

Запись экрана из среды ассистента не удалась (`could not create image from
window`); PNG-скриншоты не подменялись сгенерированными изображениями.
Фактические выводы команд сохранены в текстовых файлах выше.

Остаётся для полного соответствия заданию: получить/согласовать рекомендации
для PostgreSQL; провести итоговый эксперимент на 1–2 нодах вместо текущих трёх.
Pending/preemption (часть 6) и eviction/SLA (части 7–8) этим запуском не проверены.
