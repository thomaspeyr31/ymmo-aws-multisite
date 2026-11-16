#!/usr/bin/env python3
"""Crée les fichiers TEMPLATE (style) une seule fois : step-template.docx / .pptx.

Le style des livrables vit dans CES fichiers (éditables ensuite dans Word/PowerPoint).
Les générateurs (gen_step_docx.py / gen_step_pptx.py) ne font que les remplir.
Relancer ce script écrase les templates par une base neutre — à n'utiliser que pour
repartir de zéro ; sinon, restyler directement les .docx/.pptx dans Office.
"""
import os
from docx import Document
from pptx import Presentation

HERE = os.path.dirname(os.path.abspath(__file__))
TPL = os.path.join(HERE, "templates")


def main():
    os.makedirs(TPL, exist_ok=True)
    Document().save(os.path.join(TPL, "step-template.docx"))
    Presentation().save(os.path.join(TPL, "step-template.pptx"))
    print("Templates créés dans", TPL)


if __name__ == "__main__":
    main()
