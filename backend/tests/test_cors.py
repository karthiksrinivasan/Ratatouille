def test_cors_origins_parsing():
    raw = "http://localhost:3000,https://ratatouille.app"
    origins = [o.strip() for o in raw.split(",") if o.strip()]
    assert origins == ["http://localhost:3000", "https://ratatouille.app"]


def test_cors_wildcard_fallback():
    raw = "*"
    origins = [o.strip() for o in raw.split(",") if o.strip()]
    assert origins == ["*"]


def test_config_has_cors_origins():
    from app.config import Settings
    s = Settings(cors_origins="http://localhost:3000")
    assert s.cors_origins == "http://localhost:3000"
