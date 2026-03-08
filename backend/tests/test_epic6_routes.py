"""Tests for Epic 6 — Route registration (Task 6.9)."""

import pytest


class TestEpic6RouteRegistration:
    def test_vision_check_route(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        assert any("vision-check" in r for r in routes)

    def test_visual_guide_route(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        assert any("visual-guide" in r for r in routes)

    def test_taste_check_route(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        assert any("taste-check" in r for r in routes)

    def test_recover_route(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        assert any("recover" in r for r in routes)

    def test_all_under_v1_prefix(self):
        from app.main import app
        routes = [r.path for r in app.routes]
        vision_routes = [r for r in routes if any(k in r for k in ["vision-check", "visual-guide", "taste-check", "recover"])]
        for route in vision_routes:
            assert route.startswith("/v1/"), f"Route {route} not under /v1/ prefix"
