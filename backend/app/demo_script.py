"""Demo script for Ratatouille hackathon submission (Epic 7, Task 7.9).

Structured representation of the 3:30-3:50 demo flow that exercises
all 6 hackathon success criteria and all 14 UX requirements.
"""

DEMO_RECIPE_ID = "demo-aglio-e-olio"
DEMO_TARGET_RUNTIME_SECONDS = 230  # 3:50 target
DEMO_MAX_RUNTIME_SECONDS = 240  # 4:00 hard cap

DEMO_ACTS = [
    {
        "act": 0,
        "title": "Zero-Setup Proof",
        "duration_range": (15, 25),
        "beats": [
            "Open app → tap Cook Now (Seasoned Chef Buddy) — no recipe needed",
            "Call-like UX appears: voice/video-first, no keyboard",
            "Tap Start Cooking → Buddy greets with warm persona",
            "Say: 'I want something quick with eggs'",
            "Buddy gives immediate first action + timer suggestion (no recipe dependency)",
            "Interrupt mid-sentence: 'Wait, I also have cheese' — Buddy adapts instantly",
            "Buddy adjusts plan on the fly, demonstrating persona quality",
            "Exit and continue main scripted flow",
        ],
        "ux_requirements": ["UX-13"],
        "success_criteria": [4],
        "zero_setup_specific": {
            "no_recipe_dependency": True,
            "voice_first": True,
            "max_taps_to_conversation": 2,
            "persona_quality_demo": True,
            "interruption_handling_demo": True,
        },
    },
    {
        "act": 1,
        "title": "Entry & Scan",
        "duration_range": (45, 60),
        "beats": [
            "Open app → Home screen with 'Cook from Fridge or Pantry' [UX-1]",
            "Tap 'Scan Fridge' → Take 2-3 photos [UX-2]",
            "Detected ingredients appear as chips → Edit one [UX-3]",
            "Confirm ingredients → Dual-lane suggestions [UX-4]",
            "Tap 'Why this recipe?' on Aglio e Olio → Grounded explanation [UX-14]",
            "Select Aglio e Olio → Session setup [SC-2]",
        ],
        "ux_requirements": ["UX-1", "UX-2", "UX-3", "UX-4", "UX-14"],
        "success_criteria": [2],
    },
    {
        "act": 2,
        "title": "Session Setup",
        "duration_range": (15, 25),
        "beats": [
            "Ingredient checklist — confirm all available [UX-6]",
            "Choose phone setup: 'Counter (leaning)' [UX-5]",
            "Toggle ambient listen ON → Indicator appears [UX-7]",
            "Tap 'Start Cooking' [SC-6]",
        ],
        "ux_requirements": ["UX-5", "UX-6", "UX-7"],
        "success_criteria": [6],
    },
    {
        "act": 3,
        "title": "Live Cooking",
        "duration_range": (80, 100),
        "beats": [
            "Buddy greets: 'Let\\'s make Aglio e Olio!'",
            "Step 1: 'Bring water to boil' — Timer starts (8 min) [UX-8]",
            "Step 2: 'Slice garlic' — Parallel process shown",
            "USER INTERRUPTS mid-sentence: 'Wait — how much oil?' [UX-13] — Buddy stops immediately",
            "User: 'Go on' → Buddy resumes with concise summary",
            "Step 3: Pasta in water — Timer starts (9 min)",
            "Step 4: Garlic in oil — Timer starts (4 min) — P1 Conflict [UX-9]",
            "Voice: 'Does this look right?' → Vision check [UX-10, SC-3]",
            "'Show me what it should look like' → Guide image [UX-11, SC-5]",
            "Error recovery: 'Garlic got too dark' → 'Off the heat — now.' [SC-4]",
        ],
        "ux_requirements": ["UX-8", "UX-9", "UX-10", "UX-11", "UX-13"],
        "success_criteria": [3, 4, 5],
    },
    {
        "act": 4,
        "title": "Taste & Completion",
        "duration_range": (25, 30),
        "beats": [
            "Combine pasta + sauce → Prompted taste check [SC-4]",
            "User: 'It needs something' → Diagnostic flow",
            "Plate → Completion beat [UX-12]",
            "'That looks fantastic. Enjoy every bite.'",
            "Difficulty emoji: happy",
            "Memory confirmation: 'garlic on the lighter side' [SC-1]",
        ],
        "ux_requirements": ["UX-12"],
        "success_criteria": [1, 4],
    },
]

# All 14 UX requirements from PRD §13
ALL_UX_REQUIREMENTS = [
    "UX-1", "UX-2", "UX-3", "UX-4", "UX-5", "UX-6", "UX-7",
    "UX-8", "UX-9", "UX-10", "UX-11", "UX-12", "UX-13", "UX-14",
]

# All 6 hackathon success criteria from PRD §14.3
ALL_SUCCESS_CRITERIA = [1, 2, 3, 4, 5, 6]

FALLBACK_TALKING_POINTS = {
    "scan_fails": "Skip scan, manually enter ingredients, proceed to suggestions",
    "voice_fails": "Switch to text input mode, demonstrate text-based interaction",
    "vision_fails": "Show sensory fallback: 'Listen for sizzle, smell for nuttiness'",
    "guide_image_fails": "Show text description of target state instead of image",
    "timer_fails": "Use verbal time callouts instead of visual timer",
    "gemini_rate_limit": "Pre-cached responses available for demo recipe steps",
}


def validate_demo_coverage():
    """Validate that the demo script covers all requirements."""
    covered_ux = set()
    covered_sc = set()
    total_min_duration = 0
    total_max_duration = 0

    for act in DEMO_ACTS:
        covered_ux.update(act["ux_requirements"])
        covered_sc.update(act["success_criteria"])
        total_min_duration += act["duration_range"][0]
        total_max_duration += act["duration_range"][1]

    missing_ux = set(ALL_UX_REQUIREMENTS) - covered_ux
    missing_sc = set(ALL_SUCCESS_CRITERIA) - covered_sc

    return {
        "ux_covered": sorted(covered_ux),
        "ux_missing": sorted(missing_ux),
        "sc_covered": sorted(covered_sc),
        "sc_missing": sorted(missing_sc),
        "duration_range": (total_min_duration, total_max_duration),
        "fits_time_cap": total_max_duration <= DEMO_MAX_RUNTIME_SECONDS,
        "all_ux_covered": len(missing_ux) == 0,
        "all_sc_covered": len(missing_sc) == 0,
        "valid": len(missing_ux) == 0 and len(missing_sc) == 0 and total_max_duration <= DEMO_MAX_RUNTIME_SECONDS,
    }
