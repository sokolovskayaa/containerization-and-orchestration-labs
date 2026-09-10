from typing import Any, Optional
from flask import Flask, request, Response

app = Flask(__name__)

memory: list[bytearray] = []

@app.route("/health")
def health():
    return "ok"

@app.route("/eat")
def eat():
    query_arg: Optional[Any] = request.args.get('mb')
    if query_arg is None:
        return Response("", 400)
    query_arg_int = int(query_arg)
    query_mbytes = query_arg_int * 1024 * 1024
    allocated = bytearray(query_mbytes)
    memory.append(allocated)
    return Response(f"successfully allocated {query_arg_int} mb", 200)

@app.route("/burn")
def burn():
    while True:
        _ = 1000**1000