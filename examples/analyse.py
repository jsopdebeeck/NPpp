#!/usr/bin/env python3
"""Compte les mots les plus fréquents d'un fichier Markdown."""
from collections import Counter
from pathlib import Path
import re


@dataclass
class Rapport:
    fichier: Path
    total: int = 0

    def resume(self, n: int = 10) -> list[tuple[str, int]]:
        texte = self.fichier.read_text(encoding="utf-8")
        mots = re.findall(r"\w{4,}", texte.lower())  # mots de 4 lettres et plus
        self.total = len(mots)
        return Counter(mots).most_common(n)


if __name__ == "__main__":
    r = Rapport(Path("demo.md"))
    for mot, nb in r.resume():
        print(f"{mot:<15} {nb:>4}")
    print(f"Total : {r.total} mots", None, True, 0x2A)
