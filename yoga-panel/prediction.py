"""Offline RU/EN prefix completion; never records or changes typed text.

Dictionary data has separate CC BY-SA 4.0 terms: see data/ATTRIBUTION.md.
"""

from bisect import bisect_left
import heapq
from pathlib import Path


class Predictor:
    """Load frequency lists lazily and suggest complete words, by frequency."""

    def __init__(self, base_dir=None):
        self.base_dir = Path(base_dir) if base_dir is not None else Path(__file__).resolve().parent / "data"
        self._dictionaries = {}

    def _load(self, language):
        if language not in self._dictionaries:
            frequencies = {}
            with (self.base_dir / f"{language}_50k.txt").open(encoding="utf-8") as source:
                for line in source:
                    fields = line.rsplit(maxsplit=1)
                    if len(fields) != 2:
                        continue
                    word, count_text = fields
                    word = word.lower()
                    if not word.isalpha():
                        continue
                    # Do not mix alphabets or subtitle markup into suggestions.
                    if language == "en" and not all("a" <= c <= "z" for c in word):
                        continue
                    if language == "ru" and not all("а" <= c <= "я" or c == "ё" for c in word):
                        continue
                    try:
                        count = int(count_text)
                    except ValueError:
                        continue
                    if count <= 0:
                        continue
                    frequencies[word] = max(count, frequencies.get(word, 0))
            words = sorted(frequencies)
            self._dictionaries[language] = (words, frequencies)
        return self._dictionaries[language]

    def suggest(self, prefix, language, limit=3):
        if not isinstance(prefix, str) or len(prefix) < 2 or not prefix.isalpha():
            return []
        if language not in ("ru", "en") or not isinstance(limit, int) or limit < 1:
            return []
        normalized = prefix.lower()
        words, frequencies = self._load(language)
        start = bisect_left(words, normalized)
        end = bisect_left(words, normalized + "\U0010ffff")
        # Yield only strict completions. Deterministic alphabetic tie-breaking.
        candidates = (words[i] for i in range(start, end) if words[i] != normalized)
        best = heapq.nsmallest(limit, candidates, key=lambda word: (-frequencies[word], word))
        if prefix.isupper():
            return [word.upper() for word in best]
        if prefix.istitle():
            return [word.title() for word in best]
        # Preserve even mixed casing in the characters the user already entered.
        return [prefix + word[len(prefix):] for word in best]
