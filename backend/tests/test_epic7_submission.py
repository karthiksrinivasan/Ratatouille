"""Tests for Epic 7, Task 7.10 — Submission artifacts and Devpost checklist."""

import pytest

from app.submission import (
    ARCHITECTURE_COMPONENTS,
    DEVPOST_CHECKLIST,
    JUDGING_ALIGNMENT,
    SubmissionArtifact,
    get_checklist_status,
    validate_architecture_diagram,
)


class TestDevpostChecklist:
    """Tests for the DEVPOST_CHECKLIST constant."""

    def test_checklist_has_7_items(self):
        assert len(DEVPOST_CHECKLIST) == 7

    def test_all_items_are_required(self):
        for item in DEVPOST_CHECKLIST:
            assert item.required is True, f"{item.name} should be required"

    def test_all_items_are_submission_artifacts(self):
        for item in DEVPOST_CHECKLIST:
            assert isinstance(item, SubmissionArtifact)


class TestGetChecklistStatus:
    """Tests for get_checklist_status()."""

    def test_returns_correct_counts(self):
        # Reset all to not completed
        for item in DEVPOST_CHECKLIST:
            item.completed = False

        status = get_checklist_status()
        assert status["total"] == 7
        assert status["completed"] == 0
        assert status["required_total"] == 7
        assert status["required_completed"] == 0
        assert status["ready_to_submit"] is False
        assert len(status["items"]) == 7

    def test_marking_items_complete_updates_status(self):
        # Reset all
        for item in DEVPOST_CHECKLIST:
            item.completed = False

        # Mark first two as complete
        DEVPOST_CHECKLIST[0].completed = True
        DEVPOST_CHECKLIST[1].completed = True

        status = get_checklist_status()
        assert status["completed"] == 2
        assert status["required_completed"] == 2
        assert status["ready_to_submit"] is False

        # Mark all as complete
        for item in DEVPOST_CHECKLIST:
            item.completed = True

        status = get_checklist_status()
        assert status["completed"] == 7
        assert status["required_completed"] == 7
        assert status["ready_to_submit"] is True

        # Cleanup: reset
        for item in DEVPOST_CHECKLIST:
            item.completed = False


class TestArchitectureComponents:
    """Tests for ARCHITECTURE_COMPONENTS and validate_architecture_diagram()."""

    def test_has_all_expected_components(self):
        expected = {"mobile", "cloud_run", "firestore", "gcs", "vertex_ai", "firebase_auth"}
        assert set(ARCHITECTURE_COMPONENTS.keys()) == expected

    def test_validate_architecture_diagram_returns_valid(self):
        result = validate_architecture_diagram()
        assert result["valid"] is True
        assert result["unimplemented"] == []
        assert len(result["components"]) == 6


class TestJudgingAlignment:
    """Tests for JUDGING_ALIGNMENT."""

    def test_has_3_categories(self):
        assert len(JUDGING_ALIGNMENT) == 3

    def test_correct_weights(self):
        assert JUDGING_ALIGNMENT["innovation_ux"]["weight"] == "40%"
        assert JUDGING_ALIGNMENT["technical"]["weight"] == "30%"
        assert JUDGING_ALIGNMENT["demo_presentation"]["weight"] == "30%"

    def test_evidence_lists_are_non_empty(self):
        for category, data in JUDGING_ALIGNMENT.items():
            assert len(data["evidence"]) > 0, f"{category} has empty evidence list"
