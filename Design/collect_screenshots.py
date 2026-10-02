"""Copies the landing page screenshots out of an exported xcresult bundle.

    python3 Design/collect_screenshots.py <exported-attachments-dir> <output-dir>
"""
import json
import os
import shutil
import sys

source, target = sys.argv[1], sys.argv[2]
os.makedirs(target, exist_ok=True)
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "").split("_0_")[0]
        path = os.path.join(source, attachment["exportedFileName"])
        if name.startswith("landing-") and path.endswith(".png"):
            shutil.copy(path, os.path.join(target, name + ".png"))
            print("saved", os.path.join(target, name + ".png"))
