"""Tests for Epic 6 — Recovery Guide Agent + Endpoint (Task 6.8)."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch


class TestRecoveryAgent:
    def test_imports(self):
        from app.agents.recovery import build_recovery_prompt, RECOVERY_INSTRUCTION
        assert callable(build_recovery_prompt)
        assert "IMMEDIATE ACTION" in RECOVERY_INSTRUCTION

    def test_build_recovery_prompt(self):
        from app.agents.recovery import build_recovery_prompt
        prompt = build_recovery_prompt(
            "Aglio e Olio", 4, "Saute garlic until golden", "garlic is burnt"
        )
        assert "Aglio e Olio" in prompt
        assert "step 4" in prompt
        assert "garlic is burnt" in prompt
        assert "IMMEDIATE ACTION" in prompt
        assert "ACKNOWLEDGMENT" in prompt
        assert "HONEST ASSESSMENT" in prompt
        assert "CONCRETE PATH FORWARD" in prompt

    def test_recovery_instruction_tone(self):
        from app.agents.recovery import RECOVERY_INSTRUCTION
        assert "blame" in RECOVERY_INSTRUCTION.lower()
        assert "shame" in RECOVERY_INSTRUCTION.lower()
        assert "calm" in RECOVERY_INSTRUCTION.lower()


def _mock_session(uid="u1", recipe_id="r1", current_step=1):
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {
        "uid": uid,
        "recipe_id": recipe_id,
        "current_step": current_step,
        "status": "active",
    }
    return doc


def _mock_recipe():
    doc = MagicMock()
    doc.exists = True
    doc.to_dict.return_value = {
        "title": "Aglio e Olio",
        "steps": [
            {"step_number": 1, "instruction": "Saute garlic", "technique_tags": ["sauteing"]},
            {"step_number": 2, "instruction": "Cook pasta", "technique_tags": ["boiling"]},
        ],
    }
    return doc


class TestRecoverEndpoint:
    @pytest.mark.asyncio
    async def test_recover_success(self):
        from app.routers.vision import recover

        mock_session_doc = _mock_session()
        mock_recipe_doc = _mock_recipe()

        mock_collection = MagicMock()
        mock_doc_ref = MagicMock()
        mock_doc_ref.get = AsyncMock(side_effect=[mock_session_doc, mock_recipe_doc])
        mock_collection.document.return_value = mock_doc_ref

        mock_gemini_response = MagicMock()
        mock_gemini_response.text = "Take pan off heat now! It happens to everyone. Still salvageable. Pick out dark pieces."

        mock_aio = MagicMock()
        mock_aio.models.generate_content = AsyncMock(return_value=mock_gemini_response)

        with patch("app.routers.vision.db") as mock_db, \
             patch("app.routers.vision.gemini_client") as mock_client, \
             patch("app.routers.vision.log_session_event", new_callable=AsyncMock):
            mock_db.collection.return_value = mock_collection
            mock_client.aio = mock_aio

            result = await recover(
                session_id="s1",
                error_description="garlic is burnt",
                user={"uid": "u1"},
            )

        assert result["type"] == "recovery"
        assert "pan off heat" in result["message"].lower()
        assert result["step"] == 1
        assert "sauteing" in result["techniques_affected"]

    @pytest.mark.asyncio
    async def test_recover_logs_event(self):
        from app.routers.vision import recover

        mock_session_doc = _mock_session()
        mock_recipe_doc = _mock_recipe()

        mock_collection = MagicMock()
        mock_doc_ref = MagicMock()
        mock_doc_ref.get = AsyncMock(side_effect=[mock_session_doc, mock_recipe_doc])
        mock_collection.document.return_value = mock_doc_ref

        mock_gemini_response = MagicMock()
        mock_gemini_response.text = "Recovery advice here."

        mock_aio = MagicMock()
        mock_aio.models.generate_content = AsyncMock(return_value=mock_gemini_response)

        mock_log = AsyncMock()

        with patch("app.routers.vision.db") as mock_db, \
             patch("app.routers.vision.gemini_client") as mock_client, \
             patch("app.routers.vision.log_session_event", mock_log):
            mock_db.collection.return_value = mock_collection
            mock_client.aio = mock_aio

            await recover(
                session_id="s1",
                error_description="sauce broke",
                user={"uid": "u1"},
            )

        mock_log.assert_called_once()
        call_args = mock_log.call_args
        assert call_args[0][1] == "error_recovery"
        assert "sauce broke" in call_args[0][2]["error"]
