#!/usr/bin/env python3
"""Génère le PowerPoint d'un step (base de la présentation finale) depuis un YAML.

Contrat (règles projet) :
- AUCUNE donnée dans ce script : tout vient du YAML.
- AUCUN style en dur : le style/les layouts viennent du template .pptx ; ce script
  ne fait que choisir un layout et remplir des placeholders.
Chemins d'images relatifs au répertoire du fichier de sortie (dossier du step).
"""
import argparse
import os
import yaml
from pptx import Presentation
from pptx.util import Inches

LAYOUTS = {"title": 0, "section": 2, "content": 1, "image": 5, "table": 5}


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _title(slide, text):
    if slide.shapes.title is not None:
        slide.shapes.title.text = text or ""


def slide_title(prs, slide, spec, base):
    _title(slide, spec.get("title"))
    if len(slide.placeholders) > 1:
        slide.placeholders[1].text = spec.get("subtitle", "")


def slide_content(prs, slide, spec, base):
    _title(slide, spec.get("title"))
    body = slide.placeholders[1].text_frame
    body.clear()
    for i, item in enumerate(spec.get("bullets", [])):
        para = body.paragraphs[0] if i == 0 else body.add_paragraph()
        para.text = str(item)


def slide_image(prs, slide, spec, base):
    _title(slide, spec.get("title"))
    slide.shapes.add_picture(os.path.join(base, spec["image"]),
                             Inches(spec.get("left_in", 0.6)),
                             Inches(spec.get("top_in", 1.5)),
                             width=Inches(spec.get("width_in", 8.5)))


def slide_table(prs, slide, spec, base):
    _title(slide, spec.get("title"))
    headers, rows = spec.get("headers", []), spec.get("rows", [])
    shape = slide.shapes.add_table(len(rows) + 1, len(headers),
                                   Inches(0.6), Inches(1.6),
                                   Inches(8.8), Inches(0.4))
    for i, head in enumerate(headers):
        shape.table.cell(0, i).text = str(head)
    for r, row in enumerate(rows, start=1):
        for c, val in enumerate(row):
            shape.table.cell(r, c).text = str(val)


BUILDERS = {"title": slide_title, "section": slide_title,
            "content": slide_content, "image": slide_image,
            "table": slide_table}


def build(data, template, base):
    prs = Presentation(template)
    for spec in data.get("slides", []):
        kind = spec.get("layout", "content")
        slide = prs.slides.add_slide(prs.slide_layouts[LAYOUTS[kind]])
        BUILDERS[kind](prs, slide, spec, base)
    return prs


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
    print("PowerPoint généré :", args.out)


if __name__ == "__main__":
    main()
