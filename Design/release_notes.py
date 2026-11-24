"""Prints the section of CHANGELOG.md for one version, as the notes of a release.

    python3 Design/release_notes.py 1.15.0
"""
import re
import sys

version = sys.argv[1]
text = open("CHANGELOG.md", encoding="utf-8").read()
match = re.search(r"^## \[?" + re.escape(version) + r"\]?.*?$(.*?)(?=^## |\Z)", text, re.S | re.M)
print(match.group(1).strip() if match else f"MailMeG {version}")
