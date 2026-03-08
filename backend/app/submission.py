"""Submission artifacts and Devpost checklist (Epic 7, Task 7.10).

Tracks all required submission assets per PRD §21 and NFR-08.
"""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class SubmissionArtifact:
    name: str
    description: str
    required: bool = True
    completed: bool = False
    path: Optional[str] = None
    notes: str = ""


DEVPOST_CHECKLIST = [
    SubmissionArtifact(
        name="category_selection",
        description="Category: 'Live Agents' selected on Devpost",
        required=True,
    ),
    SubmissionArtifact(
        name="demo_video",
        description="Demo video uploaded, runtime verified < 4:00",
        required=True,
        notes="Must show: scan, suggestions, live cooking, barge-in, guide image",
    ),
    SubmissionArtifact(
        name="demo_video_content",
        description="Demo shows scan, suggestions, live cooking, barge-in, guide image",
        required=True,
    ),
    SubmissionArtifact(
        name="public_repo",
        description="Public repo link works, README has setup/deploy instructions",
        required=True,
    ),
    SubmissionArtifact(
        name="architecture_diagram",
        description="Architecture diagram attached, consistent with implementation",
        required=True,
        notes="Must match implemented system — no speculative boxes",
    ),
    SubmissionArtifact(
        name="cloud_deployment_proof",
        description="Cloud deployment proof included (screenshot or recording)",
        required=True,
    ),
    SubmissionArtifact(
        name="project_description",
        description="Project description states novelty and judging-criteria alignment",
        required=True,
    ),
]


ARCHITECTURE_COMPONENTS = {
    "mobile": {
        "name": "Flutter Mobile App",
        "description": "Cross-platform mobile client",
        "implemented": True,
    },
    "cloud_run": {
        "name": "Cloud Run (FastAPI)",
        "description": "Backend API server",
        "implemented": True,
    },
    "firestore": {
        "name": "Firestore",
        "description": "Document database for sessions, recipes, users",
        "implemented": True,
    },
    "gcs": {
        "name": "Cloud Storage",
        "description": "Media storage for images and artifacts",
        "implemented": True,
    },
    "vertex_ai": {
        "name": "Vertex AI (Gemini)",
        "description": "AI model serving for vision, voice, and text",
        "implemented": True,
    },
    "firebase_auth": {
        "name": "Firebase Auth",
        "description": "User authentication",
        "implemented": True,
    },
}


JUDGING_ALIGNMENT = {
    "innovation_ux": {
        "weight": "40%",
        "evidence": [
            "Multimodal loop: scan → voice → vision → guide image",
            "Distinct buddy persona with warm, consistent character",
            "Barge-in interruption handling for natural conversation",
            "Confidence-aware language (no false certainty)",
        ],
    },
    "technical": {
        "weight": "30%",
        "evidence": [
            "Cloud Run + Firestore + Vertex AI architecture",
            "Grounded explanations with source attribution",
            "Graceful degradation on partial failures",
            "Real-time WebSocket communication",
        ],
    },
    "demo_presentation": {
        "weight": "30%",
        "evidence": [
            "Tight 3:45 story arc covering all success criteria",
            "Every moment purposeful, no dead air",
            "Real working software, not mockups",
            "Error recovery demonstrated live",
        ],
    },
}


def get_checklist_status():
    """Return the current status of all submission artifacts."""
    total = len(DEVPOST_CHECKLIST)
    completed = sum(1 for a in DEVPOST_CHECKLIST if a.completed)
    required_total = sum(1 for a in DEVPOST_CHECKLIST if a.required)
    required_completed = sum(1 for a in DEVPOST_CHECKLIST if a.required and a.completed)

    return {
        "total": total,
        "completed": completed,
        "required_total": required_total,
        "required_completed": required_completed,
        "ready_to_submit": required_completed == required_total,
        "items": [
            {
                "name": a.name,
                "description": a.description,
                "required": a.required,
                "completed": a.completed,
                "notes": a.notes,
            }
            for a in DEVPOST_CHECKLIST
        ],
    }


def validate_architecture_diagram():
    """Verify all architecture components are implemented (no speculative boxes)."""
    unimplemented = [
        name for name, comp in ARCHITECTURE_COMPONENTS.items()
        if not comp["implemented"]
    ]
    return {
        "valid": len(unimplemented) == 0,
        "components": list(ARCHITECTURE_COMPONENTS.keys()),
        "unimplemented": unimplemented,
    }
