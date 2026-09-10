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