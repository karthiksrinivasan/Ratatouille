"""Safety and confidence constraints for freestyle cooking guidance (Epic 9, Task 9.8).

Ensures advice remains useful and safe without structured recipe constraints.
"""

# High-risk cooking situations that require immediate, firm warnings
HIGH_RISK_KEYWORDS = {
    "hot oil": "Be careful with hot oil — keep a lid nearby in case it splatters.",
    "deep fry": "Deep frying needs attention. Keep water away from hot oil, and don't overcrowd.",
    "raw chicken": "Make sure chicken reaches 165°F / 74°C internal temp. No pink inside.",
    "raw meat": "Cook meat to safe internal temps. Use a thermometer if you have one.",
    "raw pork": "Pork should reach 145°F / 63°C. Let it rest 3 minutes after cooking.",
    "raw fish": "If not sushi-grade, cook fish to 145°F / 63°C.",
    "boiling": "Watch that pot — boil-overs happen fast.",
    "pressure cooker": "Never open a pressure cooker while it's pressurized.",
    "burn": "If something's burning, pull it off the heat immediately.",
    "fire": "If there's a grease fire, smother it with a lid — never use water.",
    "allergic": "I can't verify allergens. If someone has allergies, double-check all ingredients.",
    "cross contamination": "Use separate cutting boards for raw meat and vegetables.",
    "food safety": "When in doubt, use a food thermometer. Undercooked food isn't worth the risk.",
}

# Confidence thresholds
CONFIDENCE_LEVELS = {
    "high": "Buddy is confident and gives direct instructions",
    "medium": "Buddy hedges slightly and suggests verification",
    "low": "Buddy asks clarifying questions instead of asserting",
}


def check_safety_triggers(text: str) -> list[dict]:
    """Check user input or context for safety-relevant keywords.

    Returns a list of safety warnings that should be included in the response.
    """
    warnings = []
    text_lower = text.lower()
    for keyword, warning in HIGH_RISK_KEYWORDS.items():
        if keyword in text_lower:
            warnings.append({
                "trigger": keyword,
                "warning": warning,
                "priority": "high",
            })
    return warnings


def assess_confidence(context: dict) -> str:
    """Assess the buddy's confidence level given the current freestyle context.

    Returns: "high", "medium", or "low"
    """
    score = 0

    # More context = more confidence
    if context.get("dish_goal"):
        score += 2
    if context.get("available_ingredients"):
        ingredients = context["available_ingredients"]
        if isinstance(ingredients, list) and len(ingredients) >= 2:
            score += 2
        elif isinstance(ingredients, list) and len(ingredients) >= 1:
            score += 1
    if context.get("time_budget_minutes"):
        score += 1
    if context.get("equipment"):
        score += 1
    if context.get("skill_self_rating"):
        score += 1

    if score >= 4:
        return "high"
    elif score >= 2:
        return "medium"
    return "low"


# Safety rules embedded in the freestyle instruction (already in orchestrator.py)
SAFETY_INSTRUCTION_ADDENDUM = """
## Safety Constraints (ALWAYS ACTIVE)
- If confidence is low, ask a clarifying question instead of asserting certainty
- Prioritize irreversible-risk warnings: burning oil, overcooking, food safety temperatures
- Never fabricate references to non-existent recipe steps
- If user mentions allergens or dietary restrictions, flag them prominently
- For raw meat/poultry, always mention safe internal temperatures
- If something sounds dangerous (fire, hot oil splatter), give an immediate safety warning
- Keep advice grounded in user-provided context — don't invent ingredients they haven't mentioned
"""
