from collections import Counter, defaultdict
import csv
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "docs" / "FEATURE_SPREADSHEET.csv"
with path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))

print("rows", len(rows))
print("statuses")
for key, value in sorted(Counter(row["status"] for row in rows).items()):
    print(f"{key}\t{value}")

print("areas")
area_status = defaultdict(Counter)
for row in rows:
    area_status[row["area"]][row["status"]] += 1
for area in sorted(area_status):
    details = ", ".join(f"{status}={count}" for status, count in sorted(area_status[area].items()))
    print(f"{area}\t{details}")

print("non_pass")
for row in rows:
    if row["status"] != "PASS":
        print("\t".join([row["area"], row["id"], row["name"], row["status"], row["test_coverage"], row["notes"]]))
