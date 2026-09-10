# Lab 1
## Установка
1. Необходим Python версии 3.xx (https://www.python.org/downloads/)
2. `python3 -m venv .venv`
3. `source .venv/bin/activate`
4. `pip install -r requirements.txt`

## Запуск
1. `flask --app main run`
- `http://127.0.0.1:5000/health`
- `http://127.0.0.1:5000/eat?mb=N`
- `http://127.0.0.1:5000/burn`

## Мониторинг
- Посмотреть потребление ресурсов: `ps -eo pid,vsz,rss,%mem,%cpu,comm | grep [p]ython3` / `top -p $(pgrep -d ',' 'python')`

## Часть 0
Написал минимальный веб-сервис на flask (python):
- Для `GET /eat?mb=N` создаю объект `bytearray(N)` и помещаю в список `memory: list[bytearray]` (так как этот список в global scope, garbage collector не будет очищать его и память будет оставаться занятой на протяжении всей жизни процесса)
- Для `GET /burn` сделал бесконечный цикл с возведением в степень:
```
    while True:
        _ = 1000**1000
```

## Часть 1
1 вывод ps - после /health
2, 3 вывод ps - после /eat?mb=500 (видно что vsz, rss, %mem увеличились)
После 3 вывода ps пошел /burn, Ryzen 5 7520U начал реветь🔥
![скрин 1](https://private-user-images.githubusercontent.com/149619137/647904918-4130a22c-e650-48ad-9706-45510e1f74b8.png?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3ODkwMzc1NDQsIm5iZiI6MTc4OTAzNzI0NCwicGF0aCI6Ii8xNDk2MTkxMzcvNjQ3OTA0OTE4LTQxMzBhMjJjLWU2NTAtNDhhZC05NzA2LTQ1NTEwZTFmNzRiOC5wbmc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjYwOTEwJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI2MDkxMFQxMDQ3MjRaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT0xMDU1MzVkNGEyNzJhMjAwNTZiNWY3NjFkNjE2NzY4YWIwOWIyMDRlMzcxNzkwMGIyN2ZlYjQzZjNhMGM4NTViJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCZyZXNwb25zZS1jb250ZW50LXR5cGU9aW1hZ2UlMkZwbmcifQ.t_8_wk0XjLT2SJbdQUfj9BkQFpLM3VdtcZppoVOFbNI)