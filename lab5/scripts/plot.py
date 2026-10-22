import csv
from datetime import datetime, timezone

import matplotlib.pyplot as plt

def load_csv(path):
    with open(path) as f:
        return list(csv.DictReader(f))

requests = load_csv("evidence/requests.csv")
chaos = load_csv("evidence/chaos.csv")

def timestamp(value):
    return datetime.fromtimestamp(
        int(value), tz=timezone.utc
    )

times = [timestamp(r["timestamp"]) for r in requests]
success = [1 if r["status"] == "201" else 0 for r in requests]

fig, ax = plt.subplots(figsize=(12, 4))

ax.plot(times, success, "o", markersize=3, label="HTTP requests")

for i, event in enumerate(chaos):
    ax.axvline(
        timestamp(event["timestamp"]),
        linestyle="--",
        alpha=0.4,
        label="Pod deleted" if i == 0 else None,
    )

ax.set_yticks([0, 1], ["Failure", "Success"])
ax.set_ylim(-0.2, 1.2)
ax.set_xlabel("Time (UTC)")
ax.set_title(
    f"Shop availability under chaos: "
    f"{success.count(0)} failed / {len(success)} requests"
)
ax.legend()
ax.grid(alpha=0.2)

fig.autofmt_xdate()
plt.tight_layout()
plt.savefig("evidence/availability.png", dpi=160)