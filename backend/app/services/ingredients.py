import re


def normalize_ingredient(name: str) -> str:
    """Normalize ingredient name for matching.
    'Red Onions' -> 'red onion'
    'Chicken Breasts (boneless)' -> 'chicken breast'
    """
    name = name.lower().strip()
    # Remove parenthetical qualifiers
    name = re.sub(r"\([^)]*\)", "", name).strip()
    # Remove trailing 's' for basic depluralization
    if name.endswith("es") and not name.endswith("ies"):
        name = name[:-2] if name[-3] in "shxz" else name[:-1]
    elif name.endswith("ies"):
        name = name[:-3] + "y"
    elif name.endswith("s") and not name.endswith("ss"):
        name = name[:-1]
    return name.strip()


def match_ingredients(available: list[str], required: list[str]) -> dict:
    """Match available ingredients against required ones.
    Returns {matched: [...], missing: [...], match_score: float}
    """
    available_norm = {normalize_ingredient(i) for i in available}
    required_norm = [normalize_ingredient(i) for i in required]

    matched = [r for r in required_norm if r in available_norm]
    missing = [r for r in required_norm if r not in available_norm]

    score = len(matched) / len(required_norm) if required_norm else 0.0

    return {
        "matched": matched,
        "missing": missing,
        "match_score": round(score, 2),
    }
