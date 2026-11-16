#!/usr/bin/env python3
"""Génère la documentation Word d'un step à partir d'un YAML + d'un template.

Contrat (règles projet) :
- AUCUNE donnée dans ce script : tout le contenu vient du YAML.
- AUCUN style en dur : seul le template .docx porte le style ; ce script ne
  référence que des noms de styles déjà présents dans le template.
Les chemins d'images du YAML sont relatifs au répertoire du fichier de sortie
(le dossier du step), ce qui permet d'embarquer les schémas du step.
"""
import argparse
import os
import yaml
from docx import Document
from docx.shared import Inches


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def add_paragraph(doc, block, base):
    doc.add_paragraph(block.get("text", ""), style=block.get("style"))


def add_bullets(doc, block, base):
    for item in block.get("items", []):
        doc.add_paragraph(str(item), style="List Bullet")


def add_table(doc, block, base):
    headers = block.get("headers", [])
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = block.get("style", "Table Grid")
    for i, head in enumerate(headers):
        table.rows[0].cells[i].text = str(head)
    for row in block.get("rows", []):
        cells = table.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = str(val)


def add_image(doc, block, base):
    doc.add_picture(os.path.join(base, block["path"]),
                    width=Inches(block.get("width_in", 6.3)))
    if block.get("caption"):
        doc.add_paragraph(block["caption"], style="Caption")


BLOCKS = {"paragraph": add_paragraph, "bullets": add_bullets,
          "table": add_table, "image": add_image}


def add_section(doc, section, base):
    doc.add_heading(section["heading"], level=section.get("level", 1))
    for block in section.get("body", []):
        BLOCKS[block["type"]](doc, block, base)


def build(data, template, base):
    doc = Document(template)
    doc.add_heading(data["step"]["title"], level=0)
    if data["step"].get("subtitle"):
        doc.add_paragraph(data["step"]["subtitle"], style="Subtitle")
    for section in data.get("sections", []):
        add_section(doc, section, base)
    return doc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--yaml", required=True)
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    data = load_yaml(args.yaml)
    base = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(base, exist_ok=True)
    build(data, args.template, base).save(args.out)
    print("Word généré :", args.out)


if __name__ == "__main__":
    main()
