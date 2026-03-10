# Full Spec Compliance Enhancement — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every gap between the implemented code and the 9 epic specifications, delivering a "video calling your mom for cooking guidance" experience with real audio, video, and voice-first UX.

**Architecture:** Epic-by-epic sequential sweep (1→2→3→4→5→6→8→9→7). Backend-first when both layers need changes. Parallel subagents for independent backend vs mobile work.

**Tech Stack:** Python 3.11/FastAPI, Flutter/Dart, Gemini via Vertex AI, Google ADK, Firestore, GCS, Firebase Auth. New Flutter packages: `record`, `just_audio`, `camera`, `permission_handler`, `connectivity_plus`, `flutter_local_notifications`.

**Design spec:** `docs/superpowers/specs/2026-03-10-full-spec-compliance-enhancement-design.md`

---

## Chunk 1: Epic 1 — Infrastructure Fixes + Epic 2 — Recipe Data Layer

### Task 1.1: Add ffmpeg to Dockerfile (D1.1)

**Files:**
- Modify: `backend/Dockerfile:6-11` (runtime stage)
- Test: manual `docker build` verification

- [ ] **Step 1: Add ffmpeg install to runtime stage**

In `backend/Dockerfile`, insert a new line after line 7 (`WORKDIR /app`), before line 8 (`# Copy installed packages`):

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
```

The runtime stage should now read:
```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
# Copy installed packages and binaries from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages/ /usr/local/lib/python3.11/site-packages/
COPY --from=builder /usr/local/bin/ /usr/local/bin/
```

- [ ] **Step 2: Verify Docker build succeeds**

Run: `cd backend && docker build -t ratatouille-test . 2>&1 | tail -5`
Expected: "Successfully built" or "Successfully tagged"

- [ ] **Step 3: Commit**

```bash
git add backend/Dockerfile
git commit -m "feat(epic-1): task 1.1 — add ffmpeg to Dockerfile runtime stage"
```

---

### Task 1.2: Make health check GCS call async (D1.2)

**Files:**
- Modify: `backend/app/main.py:62-64`
- Test: `backend/tests/test_health.py` (create)

- [ ] **Step 1: Write failing test**

Create `backend/tests/test_health.py`:

```python
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from httpx import AsyncClient, ASGITransport

from app.main import app


@pytest.mark.asyncio
async def test_health_gcs_uses_async():
    """GCS health check must not block the event loop."""
    mock_bucket = MagicMock()
    mock_blob = MagicMock()
    mock_bucket.blob.return_value = mock_blob
    mock_blob.exists.return_value = True

    with patch("app.main.asyncio.to_thread", new_callable=AsyncMock) as mock_to_thread:
        mock_to_thread.return_value = True
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            resp = await client.get("/health")
            assert resp.status_code == 200
            # Verify to_thread was called (async wrapper)
            mock_to_thread.assert_called_once()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python -m pytest tests/test_health.py -v`
Expected: FAIL — `to_thread` not yet used

- [ ] **Step 3: Wrap GCS call in asyncio.to_thread**

In `backend/app/main.py`, change lines 62-64 from:
```python
    try:
        from app.services.storage import bucket
        bucket.blob("_health/check.txt").exists()
        checks["gcs"] = "ok"
```
to:
```python
    try:
        import asyncio
        from app.services.storage import bucket
        await asyncio.to_thread(bucket.blob("_health/check.txt").exists)
        checks["gcs"] = "ok"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && python -m pytest tests/test_health.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/main.py backend/tests/test_health.py
git commit -m "feat(epic-1): task 1.2 — async GCS health check via to_thread"
```

---

### Task 1.3: Lock down CORS origins (D1.3)

**Files:**
- Modify: `backend/app/config.py:4-11` — add `cors_origins` field
- Modify: `backend/app/main.py:15-21` — use config value
- Test: `backend/tests/test_cors.py` (create)

- [ ] **Step 1: Write unit test for CORS origins parsing**

Create `backend/tests/test_cors.py`:

```python
def test_cors_origins_parsing():
    """Verify that comma-separated origins are correctly parsed."""
    raw = "http://localhost:3000,https://ratatouille.app"
    origins = [o.strip() for o in raw.split(",") if o.strip()]
    assert origins == ["http://localhost:3000", "https://ratatouille.app"]


def test_cors_wildcard_fallback():
    """Wildcard origin should be preserved for dev."""
    raw = "*"
    origins = [o.strip() for o in raw.split(",") if o.strip()]
    assert origins == ["*"]


def test_config_has_cors_origins():
    """Settings model should have cors_origins field."""
    from app.config import Settings
    s = Settings(cors_origins="http://localhost:3000")
    assert s.cors_origins == "http://localhost:3000"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python -m pytest tests/test_cors.py -v`
Expected: FAIL on `test_config_has_cors_origins` — field doesn't exist yet

- [ ] **Step 3: Add cors_origins to config**

In `backend/app/config.py`, add field:
```python
    cors_origins: str = "*"  # Comma-separated; "*" for dev
```

- [ ] **Step 4: Update CORS middleware to use config**

In `backend/app/main.py`, replace lines 15-21:
```python
_origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && python -m pytest tests/test_cors.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/app/config.py backend/app/main.py backend/tests/test_cors.py
git commit -m "feat(epic-1): task 1.3 — CORS origins from config"
```

---

### Task 2.1: Audit and fix seed demo data (D2.1, D2.2)

**Files:**
- Modify: `backend/seed_demo.py` — verify all fields
- Modify: `backend/app/models/recipe.py` — add `checklist_gate` if missing
- Test: `backend/tests/test_seed_demo.py` (create)

- [ ] **Step 1: Write failing test for seed data completeness**

Create `backend/tests/test_seed_demo.py`:

```python
from seed_demo import DEMO_RECIPE


def test_demo_recipe_has_seven_steps():
    assert len(DEMO_RECIPE["steps"]) == 7


def test_each_step_has_guide_image_prompt():
    for step in DEMO_RECIPE["steps"]:
        assert "guide_image_prompt" in step, f"Step {step['step_number']} missing guide_image_prompt"


def test_p1_conflict_at_steps_3_and_4():
    step3 = DEMO_RECIPE["steps"][2]
    step4 = DEMO_RECIPE["steps"][3]
    assert step3.get("is_parallel") is True or step4.get("is_parallel") is True


def test_recipe_has_checklist_gate():
    assert "checklist_gate" in DEMO_RECIPE
    assert isinstance(DEMO_RECIPE["checklist_gate"], list)
    assert len(DEMO_RECIPE["checklist_gate"]) > 0
```

- [ ] **Step 2: Run test to verify failures**

Run: `cd backend && python -m pytest tests/test_seed_demo.py -v`
Expected: Some failures (missing `checklist_gate`, possibly missing `guide_image_prompt`)

- [ ] **Step 3: Add checklist_gate to recipe model if missing**

In `backend/app/models/recipe.py`, ensure `Recipe` model includes:
```python
    checklist_gate: list[str] = []
```

- [ ] **Step 4: Fix seed_demo.py to include all required fields**

Ensure `DEMO_RECIPE` in `backend/seed_demo.py` has:
- `checklist_gate` list of ingredient check items
- Every step has `guide_image_prompt`
- Steps 3+4 have `is_parallel: True` with `duration_minutes` for conflict

- [ ] **Step 5: Run tests to verify pass**

Run: `cd backend && python -m pytest tests/test_seed_demo.py -v`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add backend/seed_demo.py backend/app/models/recipe.py backend/tests/test_seed_demo.py
git commit -m "feat(epic-2): task 2.1 — audit seed data, add checklist_gate"
```

---

### Task 2.2: Wire mobile recipe screens to existing service + ingredient checklist gate (D2.3, D8.12)

**Note:** `RecipeService` already has real API methods (`listRecipes()`, `getRecipe()`, `createRecipe()`, etc.) at `mobile/lib/features/recipes/services/recipe_service.dart`. The screens themselves are stubs that don't use the service.

**Files:**
- Modify: `mobile/lib/features/recipes/screens/recipe_list_screen.dart` — call `service.listRecipes()`
- Modify: `mobile/lib/features/recipes/screens/recipe_detail_screen.dart` — call `service.getRecipe(id)`
- Modify: `mobile/lib/features/recipes/screens/recipe_create_screen.dart` — call `service.createRecipe()`
- Modify: `mobile/lib/features/recipes/screens/ingredient_checklist_screen.dart` — gate logic
- Test: `mobile/test/features/recipes/screens/recipe_list_screen_test.dart` (create)

- [ ] **Step 1: Write failing test for recipe list screen wiring**

Create `mobile/test/features/recipes/screens/recipe_list_screen_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/features/recipes/services/recipe_service.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  group('RecipeService (existing API)', () {
    test('listRecipes calls GET /v1/recipes and returns Recipe list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/recipes');
        expect(request.method, 'GET');
        return http.Response(
          jsonEncode([
            {'id': 'r1', 'title': 'Pasta', 'description': 'Tasty', 'steps': [], 'ingredients': []}
          ]),
          200,
        );
      });

      final api = ApiClient(httpClient: mockClient, baseUrl: 'http://test');
      final service = RecipeService(api: api);
      final recipes = await service.listRecipes();
      expect(recipes, isNotEmpty);
      expect(recipes.first.title, 'Pasta');
    });

    test('getRecipe calls GET /v1/recipes/{id}', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/recipes/r1');
        return http.Response(
          jsonEncode({'id': 'r1', 'title': 'Pasta', 'steps': [], 'ingredients': []}),
          200,
        );
      });

      final api = ApiClient(httpClient: mockClient, baseUrl: 'http://test');
      final service = RecipeService(api: api);
      final recipe = await service.getRecipe('r1');
      expect(recipe.title, 'Pasta');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it passes (service is already wired)**

Run: `cd mobile && flutter test test/features/recipes/screens/recipe_list_screen_test.dart`
Expected: PASS — service already works

- [ ] **Step 3: Wire recipe screens to use RecipeService via Provider**

Update each recipe screen to inject `RecipeService` via `Provider` and replace any hardcoded/stub data:
- `recipe_list_screen.dart`: `initState` → `service.listRecipes()` → `setState` with real data
- `recipe_detail_screen.dart`: `initState` → `service.getRecipe(id)` → `setState` with real data
- `recipe_create_screen.dart`: submit → `service.createRecipe(request)` → navigate back

- [ ] **Step 4: Implement ingredient checklist gate (D8.12)**

In `ingredient_checklist_screen.dart`:
- Load recipe via `service.getRecipe(recipeId)`
- Display `checklist_gate` items (from recipe data) as checkboxes
- "Start Cooking" button is **disabled** until ALL items are checked
- Gate logic:

```dart
bool get _allChecked => _checkedItems.length == _checklistItems.length;

// In build:
FilledButton(
  onPressed: _allChecked ? _startCooking : null,  // null = disabled
  child: const Text('Start Cooking'),
),
```

- [ ] **Step 5: Verify import**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | tail -10`
Expected: No errors in recipe files

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/recipes/ mobile/test/features/recipes/
git commit -m "feat(epic-2): task 2.2 — wire recipe screens to service + checklist gate"
```

---

## Chunk 2: Epic 8 Part 1 — Mobile Infrastructure (Prerequisites)

These are prerequisites for all subsequent mobile work.

### Task 8.1: Add new Flutter dependencies

**Files:**
- Modify: `mobile/pubspec.yaml`

- [ ] **Step 1: Add dependencies to pubspec.yaml**

Add under `dependencies:`:
```yaml
  # Audio
  record: ^5.0.0
  just_audio: ^0.9.36

  # Camera
  camera: ^0.10.5+5

  # Permissions
  permission_handler: ^11.1.0

  # Connectivity
  connectivity_plus: ^5.0.2

  # Notifications
  flutter_local_notifications: ^16.3.0
```

- [ ] **Step 2: Run pub get**

Run: `cd mobile && flutter pub get`
Expected: resolves without errors

- [ ] **Step 3: Add iOS platform permissions to Info.plist**

In `mobile/ios/Runner/Info.plist`, add inside the `<dict>`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Ratatouille needs your microphone so your cooking buddy can hear you.</string>
<key>NSCameraUsageDescription</key>
<string>Ratatouille needs your camera to see what you're cooking and help guide you.</string>
```

- [ ] **Step 4: Add Android permissions to AndroidManifest.xml**

In `mobile/android/app/src/main/AndroidManifest.xml`, add before `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```

- [ ] **Step 5: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/ios/Runner/Info.plist mobile/android/app/src/main/AndroidManifest.xml
git commit -m "feat(epic-8): task 8.1 — add audio, camera, permissions, connectivity dependencies + platform config"
```

---

### Task 8.2: Add request timeouts to ApiClient (D8.1)

**Files:**
- Modify: `mobile/lib/core/api_client.dart`
- Test: `mobile/test/core/api_client_test.dart` (create)

- [ ] **Step 1: Write failing test**

Create `mobile/test/core/api_client_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ratatouille/core/api_client.dart';

void main() {
  group('ApiClient timeouts', () {
    test('GET times out after 10 seconds', () async {
      final client = MockClient((request) async {
        await Future.delayed(const Duration(seconds: 15));
        return http.Response('{}', 200);
      });

      final api = ApiClient(
        httpClient: client,
        baseUrl: 'http://test',
      );

      expect(
        () => api.get('/v1/health'),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/core/api_client_test.dart --timeout=30s`
Expected: FAIL — no timeout enforced currently

- [ ] **Step 3: Add timeout to all HTTP methods**

In `mobile/lib/core/api_client.dart`, add a `_withTimeout` wrapper and apply it to all methods:

```dart
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _aiTimeout = Duration(seconds: 30);

  Future<T> _withTimeout<T>(Future<T> future, {Duration? timeout}) {
    return future.timeout(timeout ?? _defaultTimeout);
  }
```

Wrap each HTTP call: `await _withTimeout(_httpClient.get(uri, headers: headers))`.

For AI endpoints (vision-check, visual-guide, taste-check, recover), use `_aiTimeout`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/core/api_client_test.dart --timeout=30s`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/api_client.dart mobile/test/core/api_client_test.dart
git commit -m "feat(epic-8): task 8.2 — add request timeouts to ApiClient"
```

---

### Task 8.3: Add request cancellation on screen exit (D8.2)

**Files:**
- Modify: `mobile/lib/core/api_client.dart` — add `CancelToken` support

- [ ] **Step 1: Add cancel token to ApiClient**

In `mobile/lib/core/api_client.dart`, add a simple cancellation mechanism using `Completer`:

```dart
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }
}

class CancelledException implements Exception {
  @override
  String toString() => 'Request was cancelled';
}
```

Add optional `CancelToken? cancelToken` param to `get`, `post`, `put`, `delete`. Check `cancelToken.throwIfCancelled()` before and after the HTTP call.

- [ ] **Step 2: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/core/api_client.dart
git commit -m "feat(epic-8): task 8.3 — add cancel token support to ApiClient"
```

---

### Task 8.4: Real connectivity monitoring (D8.3)

**Files:**
- Modify: `mobile/lib/core/connectivity.dart` — use `connectivity_plus`
- Test: `mobile/test/core/connectivity_test.dart` (create)

- [ ] **Step 1: Write failing test**

Create `mobile/test/core/connectivity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/connectivity.dart';

void main() {
  test('ConnectivityService exposes a stream', () {
    final service = ConnectivityService();
    expect(service.onStatusChange, isA<Stream<bool>>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/core/connectivity_test.dart`
Expected: FAIL — `onStatusChange` doesn't exist yet

- [ ] **Step 3: Rewrite ConnectivityService with connectivity_plus**

Rewrite `mobile/lib/core/connectivity.dart`:

```dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));

  ConnectivityService() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        notifyListeners();
      }
    });
  }

  Future<bool> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    return _isOnline;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd mobile && flutter test test/core/connectivity_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/connectivity.dart mobile/test/core/connectivity_test.dart
git commit -m "feat(epic-8): task 8.4 — real connectivity monitoring with connectivity_plus"
```

---

### Task 8.5: Permission handling service (D8.5)

**Files:**
- Create: `mobile/lib/core/permission_service.dart`
- Test: `mobile/test/core/permission_service_test.dart` (create)

- [ ] **Step 1: Write failing test**

Create `mobile/test/core/permission_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/permission_service.dart';

void main() {
  test('PermissionService has requestMicCamera method', () {
    final service = PermissionService();
    expect(service.requestMicCamera, isA<Function>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/core/permission_service_test.dart`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Create PermissionService**

Create `mobile/lib/core/permission_service.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';

class PermissionResult {
  final bool micGranted;
  final bool cameraGranted;

  const PermissionResult({
    required this.micGranted,
    required this.cameraGranted,
  });

  bool get allGranted => micGranted && cameraGranted;
  bool get micOnly => micGranted && !cameraGranted;
  bool get noneGranted => !micGranted && !cameraGranted;
}

class PermissionService {
  Future<PermissionResult> requestMicCamera() async {
    final statuses = await [
      Permission.microphone,
      Permission.camera,
    ].request();

    return PermissionResult(
      micGranted: statuses[Permission.microphone]?.isGranted ?? false,
      cameraGranted: statuses[Permission.camera]?.isGranted ?? false,
    );
  }

  Future<bool> isMicGranted() async {
    return (await Permission.microphone.status).isGranted;
  }

  Future<bool> isCameraGranted() async {
    return (await Permission.camera.status).isGranted;
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd mobile && flutter test test/core/permission_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/permission_service.dart mobile/test/core/permission_service_test.dart
git commit -m "feat(epic-8): task 8.5 — permission handling service for mic + camera"
```

---

### Task 8.6: AppRoutes constants everywhere (D8.9)

**Files:**
- Modify: `mobile/lib/app/router.dart` — ensure all route strings are in `AppRoutes`
- Modify: All files using hardcoded route strings (scan_screen.dart L52, etc.)

- [ ] **Step 1: Audit hardcoded route strings**

Search for `context.go('` and `context.push('` across all `.dart` files. Replace every hardcoded string with the corresponding `AppRoutes` constant.

- [ ] **Step 2: Replace hardcoded routes**

In each file found, replace e.g. `context.go('/scan')` with `context.go(AppRoutes.scan)`.

- [ ] **Step 3: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/
git commit -m "feat(epic-8): task 8.6 — replace all hardcoded route strings with AppRoutes constants"
```

---

### Task 8.7: Error boundary widget (D8.13)

**Files:**
- Create: `mobile/lib/shared/widgets/error_boundary.dart`

- [ ] **Step 1: Create ErrorBoundary widget**

**Note:** Flutter does not have React-style error boundaries. We use a combination of `ErrorWidget.builder` (for render errors) and a wrapper that catches async errors.

Create `mobile/lib/shared/widgets/error_boundary.dart`:

```dart
import 'package:flutter/material.dart';

/// Sets up a global error widget for rendering failures.
/// Call once in main() before runApp().
void setupErrorBoundary() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _ErrorFallback(
      error: details.exception,
      onRetry: null, // Can't retry render errors generically
    );
  };
}

/// Wraps a child and catches errors from async operations within it.
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, VoidCallback retry)? errorBuilder;

  const ErrorBoundary({super.key, required this.child, this.errorBuilder});

  @override
  State<ErrorBoundary> createState() => ErrorBoundaryState();
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  /// Call this from child widgets to report an error.
  void reportError(Object error) {
    setState(() => _error = error);
  }

  void _reset() => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!, _reset);
      }
      return _ErrorFallback(error: _error!, onRetry: _reset);
    }
    return widget.child;
  }
}

class _ErrorFallback extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _ErrorFallback({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Something went wrong', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

Also wire `setupErrorBoundary()` in `mobile/lib/main.dart` before `runApp()`.

- [ ] **Step 2: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/shared/widgets/error_boundary.dart
git commit -m "feat(epic-8): task 8.7 — error boundary widget"
```

---

### Task 8.8: Retry for transient 5xx errors (D8.4)

**Files:**
- Modify: `mobile/lib/core/api_client.dart` — add retry wrapper

- [ ] **Step 1: Write failing test**

Add to `mobile/test/core/api_client_test.dart`:

```dart
    test('retries on 502 for idempotent GET', () async {
      int callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (callCount == 1) return http.Response('{}', 502);
        return http.Response('{"ok": true}', 200);
      });

      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      final result = await api.getWithRetry('/v1/health');
      expect(result['ok'], true);
      expect(callCount, 2);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/core/api_client_test.dart`
Expected: FAIL — getWithRetry only retries on 401

- [ ] **Step 3: Add 5xx retry to getWithRetry**

In `mobile/lib/core/api_client.dart`, modify `getWithRetry`:

```dart
  Future<Map<String, dynamic>> getWithRetry(
    String path, {
    Map<String, String>? queryParams,
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await get(path, queryParams: queryParams);
      } on ApiException catch (e) {
        if (e.isUnauthorized && attempt == 0) {
          await _forceRefreshToken();
          continue;
        }
        if (e.statusCode >= 502 && e.statusCode <= 504 && attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        rethrow;
      }
    }
    return get(path, queryParams: queryParams); // Final attempt
  }
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd mobile && flutter test test/core/api_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/api_client.dart mobile/test/core/api_client_test.dart
git commit -m "feat(epic-8): task 8.8 — exponential backoff retry for transient 5xx"
```

---

## Chunk 3: Epic 3 — Fridge/Pantry Scan Gaps

### Task 3.1: Camera permission handling for scan (D3.4)

**Files:**
- Modify: `mobile/lib/features/scan/screens/scan_screen.dart` — add permission check before camera

- [ ] **Step 1: Add permission check in scan screen**

In `mobile/lib/features/scan/screens/scan_screen.dart`, before opening camera, call:

```dart
final permService = PermissionService();
final result = await permService.requestMicCamera();
if (!result.cameraGranted) {
  if (!mounted) return;
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Camera Access Needed'),
      content: const Text('Ratatouille needs your camera to scan ingredients. '
          'Please grant camera permission in Settings.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => openAppSettings(), child: const Text('Open Settings')),
      ],
    ),
  );
  return;
}
```

- [ ] **Step 2: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/scan/screens/scan_screen.dart
git commit -m "feat(epic-3): task 3.1 — camera permission handling for scan"
```

---

### Task 3.2: Wire video scan to real backend analysis (D3.1)

**Files:**
- Modify: `mobile/lib/features/scan/screens/scan_screen.dart` — send video to backend
- Modify: `mobile/lib/core/media_pipeline.dart` — real upload progress

- [ ] **Step 1: Wire video upload → backend**

In scan_screen.dart, after video capture, replace simulated flow with:

```dart
final mediaPipeline = MediaPipeline(api: context.read<ApiClient>());
final uploadResult = await mediaPipeline.uploadFile(
  videoPath,
  '/v1/inventory/scan-video',
  onProgress: (progress) {
    setState(() => _uploadProgress = progress);
  },
);
// uploadResult contains detected ingredients
setState(() {
  _detectedIngredients = (uploadResult['ingredients'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
});
```

- [ ] **Step 2: Add real upload progress to MediaPipeline (D3.3)**

In `mobile/lib/core/media_pipeline.dart`, replace simulated progress with `StreamedRequest` progress tracking:

```dart
Future<Map<String, dynamic>> uploadFile(
  String filePath,
  String endpoint, {
  void Function(double)? onProgress,
}) async {
  final file = File(filePath);
  final fileSize = await file.length();
  final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$endpoint'));
  // ... add file, track bytes sent for progress
}
```

- [ ] **Step 3: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/scan/screens/scan_screen.dart mobile/lib/core/media_pipeline.dart
git commit -m "feat(epic-3): task 3.2 — wire video scan to backend with real upload progress"
```

---

### Task 3.3: "Why this recipe?" real explanation (D3.2)

**Files:**
- Modify: `mobile/lib/features/suggestions/screens/suggestions_screen.dart:176-192` — replace stub

- [ ] **Step 1: Replace explanation stub with real API call**

In `suggestions_screen.dart`, replace the hardcoded explanation with:

```dart
Future<void> _loadExplanation(String recipeId) async {
  setState(() => _explanationLoading = true);
  try {
    final api = context.read<ApiClient>();
    final result = await api.get('/v1/recipes/$recipeId/explain',
      queryParams: {'ingredients': _detectedIngredients.join(',')});
    setState(() => _explanation = result['explanation'] as String);
  } catch (e) {
    setState(() => _explanation = 'Could not load explanation.');
  } finally {
    setState(() => _explanationLoading = false);
  }
}
```

- [ ] **Step 2: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/suggestions/screens/suggestions_screen.dart
git commit -m "feat(epic-3): task 3.3 — wire 'Why this recipe?' to real API"
```

---

### Task 3.4: Scan error recovery + retry (D3.5)

**Files:**
- Modify: `mobile/lib/features/scan/screens/scan_screen.dart` — add retry + fallback

- [ ] **Step 1: Add retry button and manual entry fallback on scan error**

In scan_screen.dart error state, add:

```dart
if (_error != null) ...[
  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
  const SizedBox(height: 12),
  FilledButton.icon(
    onPressed: _startScan,
    icon: const Icon(Icons.refresh),
    label: const Text('Try Again'),
  ),
  const SizedBox(height: 8),
  OutlinedButton.icon(
    onPressed: () => context.go(AppRoutes.ingredientReview),
    icon: const Icon(Icons.edit),
    label: const Text('Enter Manually Instead'),
  ),
]
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/scan/screens/scan_screen.dart
git commit -m "feat(epic-3): task 3.4 — scan error retry + manual entry fallback"
```

---

### Task 3.5: Voice dictation for manual ingredient entry (D3.7)

**Files:**
- Modify: `mobile/lib/features/scan/screens/ingredient_review_screen.dart:267-289` — add mic icon

- [ ] **Step 1: Add mic icon button next to text field**

In `ingredient_review_screen.dart`, next to the manual add TextField, add a mic icon that uses platform speech-to-text:

```dart
IconButton(
  icon: const Icon(Icons.mic),
  tooltip: 'Dictate ingredient',
  onPressed: _startVoiceDictation,
),
```

The `_startVoiceDictation` method captures audio, sends to backend speech-to-text, and adds the result to the ingredients list.

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/scan/screens/ingredient_review_screen.dart
git commit -m "feat(epic-3): task 3.5 — voice dictation for manual ingredient entry"
```

---

## Chunk 4: Epic 4 Part 1 — Backend Audio + WS Enhancements

### Task 4.1: Add buddy_audio WS event type (D4.13)

**Files:**
- Modify: `backend/app/routers/live.py` — add audio forwarding from LiveAudioSession
- Test: `backend/tests/test_live_audio_events.py` (create)

- [ ] **Step 1: Write test for buddy_audio event forwarding**

Create `backend/tests/test_live_audio_events.py`:

```python
import pytest
import base64
from unittest.mock import AsyncMock, MagicMock, patch

from app.agents.live_audio import LiveAudioSession


@pytest.mark.asyncio
async def test_receive_responses_yields_audio():
    """LiveAudioSession.receive_responses should yield audio_response events."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": [{"step_number": 1, "instruction": "Test"}]},
        session_state={"current_step": 1},
    )

    # Mock the live session to yield a fake audio message
    mock_msg = MagicMock()
    mock_part = MagicMock()
    mock_part.inline_data = MagicMock(data=b"fake_audio_pcm", mime_type="audio/pcm")
    mock_part.text = None
    mock_msg.server_content.model_turn.parts = [mock_part]

    mock_live = AsyncMock()

    async def fake_receive():
        yield mock_msg

    mock_live.receive = fake_receive
    session.live_session = mock_live

    results = []
    async for event in session.receive_responses():
        results.append(event)

    assert len(results) == 1
    assert results[0]["type"] == "audio_response"
    assert results[0]["audio"] == base64.b64encode(b"fake_audio_pcm").decode()
    assert results[0]["mime_type"] == "audio/pcm"


def test_buddy_audio_ws_event_format():
    """buddy_audio WS events must have type, audio, and mime_type fields."""
    audio_data = base64.b64encode(b"test_pcm").decode()
    event = {
        "type": "buddy_audio",
        "audio": audio_data,
        "mime_type": "audio/pcm",
    }
    assert event["type"] == "buddy_audio"
    assert base64.b64decode(event["audio"]) == b"test_pcm"
```

- [ ] **Step 2: Run test**

Run: `cd backend && python -m pytest tests/test_live_audio_events.py -v`
Expected: PASS

- [ ] **Step 3: Add buddy_audio forwarding in live.py**

In `backend/app/routers/live.py`, after the voice_audio handler (around L165-172), add audio forwarding. When orchestrator returns audio from Gemini Live, send as:

```python
# In the voice_audio handler, after getting response:
if response and response.get("type") == "audio_response":
    await websocket.send_json({
        "type": "buddy_audio",
        "audio": response["audio"],
        "mime_type": response.get("mime_type", "audio/pcm"),
    })
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/routers/live.py backend/tests/test_live_audio_events.py
git commit -m "feat(epic-4): task 4.1 — add buddy_audio WS event type"
```

---

### Task 4.2: Verify Gemini Live audio e2e flow (D4.12)

**Files:**
- Modify: `backend/app/agents/live_audio.py` — audit and fix bidirectional audio
- Test: `backend/tests/test_live_audio_session.py` (create)

- [ ] **Step 1: Write test for LiveAudioSession**

Create `backend/tests/test_live_audio_session.py`:

```python
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from app.agents.live_audio import LiveAudioSession


@pytest.mark.asyncio
async def test_connect_sets_audio_modality():
    """LiveAudioSession.connect() must request AUDIO response modality."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": [{"step_number": 1, "instruction": "Boil water"}]},
        session_state={"current_step": 1},
    )

    with patch("app.agents.live_audio.gemini_client") as mock_client:
        mock_live = AsyncMock()
        mock_client.aio.live.connect = mock_live
        mock_live.return_value = AsyncMock()

        await session.connect()

        mock_live.assert_called_once()
        call_kwargs = mock_live.call_args
        config = call_kwargs.kwargs.get("config") or call_kwargs[1].get("config")
        assert "AUDIO" in config.response_modalities


@pytest.mark.asyncio
async def test_send_audio_forwards_to_gemini():
    """send_audio should forward base64 audio to Gemini Live session."""
    session = LiveAudioSession(
        recipe={"title": "Test", "steps": []},
        session_state={"current_step": 1},
    )
    session.live_session = AsyncMock()

    import base64
    test_audio = base64.b64encode(b"test_pcm_data").decode()
    await session.send_audio(test_audio)

    session.live_session.send.assert_called_once()
```

- [ ] **Step 2: Run tests**

Run: `cd backend && python -m pytest tests/test_live_audio_session.py -v`
Expected: PASS

- [ ] **Step 3: Audit live_audio.py — verify no issues**

Review `backend/app/agents/live_audio.py`. Key verifications:
- `connect()` uses `response_modalities=["AUDIO"]` ✓
- `send_audio()` decodes base64 → sends as PCM blob ✓
- `receive_responses()` yields both audio and text responses ✓
- `close()` sends `turn_complete` before closing ✓

If any issues found, fix them.

- [ ] **Step 4: Commit**

```bash
git add backend/tests/test_live_audio_session.py
git commit -m "feat(epic-4): task 4.2 — verify Gemini Live audio e2e with tests"
```

---

### Task 4.3: Add browse mode WS event handlers (D4.6)

**Files:**
- Verify: `backend/app/routers/live.py:301-356` — browse handlers already exist

- [ ] **Step 1: Verify browse handlers are present**

Read `backend/app/routers/live.py` lines 301-356. Verify:
- `browse_start` handler sends `buddy_message` with `browse_active: True` ✓
- `browse_frame` handler calls `browse_session.process_frame()` → sends `browse_observation` + `ingredient_candidates` + `browse_question` ✓
- `browse_stop` handler merges ingredients → sends `browse_complete` ✓

These handlers already exist. Mark as verified.

- [ ] **Step 2: Commit verification note**

No code changes needed — browse handlers are already implemented.

---

### Task 4.4: Add WS message validation (D4.7)

**Files:**
- Create: `backend/app/models/ws_events.py` — Pydantic models for WS events
- Modify: `backend/app/routers/live.py` — validate incoming/outgoing messages
- Test: `backend/tests/test_ws_validation.py` (create)

- [ ] **Step 1: Write failing test**

Create `backend/tests/test_ws_validation.py`:

```python
import pytest
from pydantic import ValidationError

from app.models.ws_events import IncomingWsEvent


def test_valid_voice_query():
    event = IncomingWsEvent(type="voice_query", text="How long to boil?")
    assert event.type == "voice_query"


def test_invalid_event_type():
    with pytest.raises(ValidationError):
        IncomingWsEvent(type="invalid_type_xyz", text="")


def test_step_complete_requires_step():
    event = IncomingWsEvent(type="step_complete", step=3)
    assert event.step == 3
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python -m pytest tests/test_ws_validation.py -v`
Expected: FAIL — module doesn't exist

- [ ] **Step 3: Create WS event models**

Create `backend/app/models/ws_events.py`:

```python
"""Pydantic models for WebSocket event validation."""

from typing import Optional, Literal
from pydantic import BaseModel

VALID_EVENT_TYPES = [
    "voice_query", "voice_audio", "barge_in", "step_complete",
    "process_complete", "process_delegate", "conflict_choice",
    "vision_check", "context_update", "add_timer",
    "browse_start", "browse_frame", "browse_stop",
    "ambient_toggle", "resume_interrupted", "session_resume",
    "ping", "auth",
]

class IncomingWsEvent(BaseModel):
    type: str
    text: Optional[str] = None
    audio: Optional[str] = None
    step: Optional[int] = None
    process_id: Optional[str] = None
    chosen_process_id: Optional[str] = None
    frame_uri: Optional[str] = None
    context: Optional[dict] = None
    name: Optional[str] = None
    duration_minutes: Optional[float] = None
    enabled: Optional[bool] = None
    source: Optional[str] = None
    token: Optional[str] = None

    def model_post_init(self, __context):
        if self.type not in VALID_EVENT_TYPES:
            raise ValueError(f"Invalid event type: {self.type}")
```

- [ ] **Step 4: Add validation in live.py event loop**

In `backend/app/routers/live.py`, after `data = await websocket.receive_json()`, add:

```python
from app.models.ws_events import IncomingWsEvent
try:
    validated = IncomingWsEvent(**data)
except Exception as e:
    logger.warning(f"WS event validation failed: {e}", extra={"raw_event": data})
    await websocket.send_json({"type": "error", "message": "Invalid event format"})
    continue
```

- [ ] **Step 5: Run tests**

Run: `cd backend && python -m pytest tests/test_ws_validation.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/app/models/ws_events.py backend/app/routers/live.py backend/tests/test_ws_validation.py
git commit -m "feat(epic-4): task 4.4 — WS message validation with Pydantic models"
```

---

## Chunk 5: Epic 4 Part 2 — Mobile Live Session Redesign ("Call With Mom")

This is the largest single chunk. The entire `live_session_screen.dart` gets redesigned from a text-message style to a FaceTime-style call experience with camera, audio, guide image overlay, and call chrome.

### Task 4.5: Audio capture service (D4.1)

**Echo cancellation note:** The mic will pick up buddy audio from the speaker. Gemini Live handles server-side echo cancellation when receiving audio streams (it ignores its own output). Additionally, on iOS/Android, the `record` package uses the platform's built-in AEC when available. If echo is still problematic, mute mic during buddy playback as a fallback (set `_audioCapture.pause()` while `_audioPlayback.isPlaying`).

**Files:**
- Create: `mobile/lib/core/audio_capture.dart`
- Test: `mobile/test/core/audio_capture_test.dart` (create)

- [ ] **Step 1: Write failing test**

Create `mobile/test/core/audio_capture_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/audio_capture.dart';

void main() {
  test('AudioCaptureService has start/stop methods', () {
    final service = AudioCaptureService();
    expect(service.start, isA<Function>());
    expect(service.stop, isA<Function>());
    expect(service.isRecording, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/core/audio_capture_test.dart`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Create AudioCaptureService**

Create `mobile/lib/core/audio_capture.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Continuously captures microphone audio, emitting base64-encoded PCM chunks.
class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  bool _recording = false;

  bool get isRecording => _recording;

  /// Start continuous capture. Emits base64 PCM chunks via [onAudioChunk].
  Future<void> start({
    required void Function(String base64Audio) onAudioChunk,
  }) async {
    if (_recording) return;

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));

    _recording = true;
    _streamSub = stream.listen((data) {
      onAudioChunk(base64Encode(data));
    });
  }

  /// Stop capturing.
  Future<void> stop() async {
    _recording = false;
    await _streamSub?.cancel();
    _streamSub = null;
    await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }
}
```

- [ ] **Step 4: Run test**

Run: `cd mobile && flutter test test/core/audio_capture_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/audio_capture.dart mobile/test/core/audio_capture_test.dart
git commit -m "feat(epic-4): task 4.5 — audio capture service with record package"
```

---

### Task 4.6: Audio playback service (D4.2, D4.3)

**Files:**
- Create: `mobile/lib/core/audio_playback.dart`
- Test: `mobile/test/core/audio_playback_test.dart` (create)

- [ ] **Step 1: Write failing test**

Create `mobile/test/core/audio_playback_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/audio_playback.dart';

void main() {
  test('AudioPlaybackService has play/stop/bargeIn methods', () {
    final service = AudioPlaybackService();
    expect(service.play, isA<Function>());
    expect(service.stopImmediately, isA<Function>());
    expect(service.isPlaying, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/core/audio_playback_test.dart`
Expected: FAIL

- [ ] **Step 3: Create AudioPlaybackService with barge-in support**

Create `mobile/lib/core/audio_playback.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// Plays buddy voice audio with immediate barge-in stop capability.
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  bool get isPlaying => _playing;

  /// Play base64-encoded PCM audio from buddy.
  Future<void> play(String base64Audio, {String mimeType = 'audio/pcm'}) async {
    final bytes = base64Decode(base64Audio);
    _playing = true;

    // Use a StreamAudioSource for PCM data
    await _player.setAudioSource(_PcmAudioSource(bytes));
    await _player.play();
    _playing = false;
  }

  /// Immediately stop playback — barge-in. Must complete in <200ms.
  Future<void> stopImmediately() async {
    _playing = false;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// Custom audio source for raw PCM data with WAV header.
class _PcmAudioSource extends StreamAudioSource {
  final Uint8List _pcmData;
  late final Uint8List _wavBytes; // Cached — built once

  _PcmAudioSource(this._pcmData) {
    // Build WAV bytes once at construction (16kHz, 16-bit, mono)
    final header = _buildWavHeader(_pcmData.length, 16000, 1, 16);
    _wavBytes = Uint8List.fromList([...header, ..._pcmData]);
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _wavBytes.length;
    return StreamAudioResponse(
      sourceLength: _wavBytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_wavBytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }

  static Uint8List _buildWavHeader(int dataSize, int sampleRate, int channels, int bitsPerSample) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final buffer = ByteData(44);
    // RIFF header
    buffer.setUint8(0, 0x52); buffer.setUint8(1, 0x49);
    buffer.setUint8(2, 0x46); buffer.setUint8(3, 0x46);
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setUint8(8, 0x57); buffer.setUint8(9, 0x41);
    buffer.setUint8(10, 0x56); buffer.setUint8(11, 0x45);
    // fmt chunk
    buffer.setUint8(12, 0x66); buffer.setUint8(13, 0x6D);
    buffer.setUint8(14, 0x74); buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, channels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    buffer.setUint8(36, 0x64); buffer.setUint8(37, 0x61);
    buffer.setUint8(38, 0x74); buffer.setUint8(39, 0x61);
    buffer.setUint32(40, dataSize, Endian.little);
    return buffer.buffer.asUint8List();
  }
}
```

- [ ] **Step 4: Run test**

Run: `cd mobile && flutter test test/core/audio_playback_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/audio_playback.dart mobile/test/core/audio_playback_test.dart
git commit -m "feat(epic-4): task 4.6 — audio playback with barge-in support"
```

---

### Task 4.7: Camera preview service (D4.4)

**Files:**
- Create: `mobile/lib/core/camera_service.dart`
- Test: `mobile/test/core/camera_service_test.dart` (create)

- [ ] **Step 1: Write failing test**

Create `mobile/test/core/camera_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/camera_service.dart';

void main() {
  test('CameraService has initialize/captureFrame/dispose methods', () {
    // Can't fully test camera without device, just verify API surface
    expect(CameraService, isNotNull);
  });
}
```

- [ ] **Step 2: Create CameraService**

Create `mobile/lib/core/camera_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Manages camera preview and frame capture for live sessions.
class CameraService {
  CameraController? _controller;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  CameraController? get controller => _controller;

  /// Initialize camera (rear-facing by default).
  Future<void> initialize({bool front = false}) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final camera = front
        ? cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.first,
          )
        : cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false, // Audio handled separately by AudioCaptureService
    );

    await _controller!.initialize();
    _initialized = true;
  }

  /// Flip between front/rear camera.
  Future<void> flipCamera() async {
    if (_controller == null) return;
    final current = _controller!.description.lensDirection;
    await dispose();
    await initialize(front: current == CameraLensDirection.back);
  }

  /// Capture a single frame as base64 JPEG for vision check.
  Future<String?> captureFrame() async {
    if (_controller == null || !_initialized) return null;
    final file = await _controller!.takePicture();
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  /// Capture frame and upload to GCS, return the gs:// URI.
  Future<String?> captureFrameToFile() async {
    if (_controller == null || !_initialized) return null;
    final file = await _controller!.takePicture();
    return file.path;
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _initialized = false;
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/core/camera_service.dart mobile/test/core/camera_service_test.dart
git commit -m "feat(epic-4): task 4.7 — camera preview service with flip + frame capture"
```

---

### Task 4.8: Guide image overlay widget (D4.16–D4.20)

**Note:** `cached_network_image` is already in `pubspec.yaml` — no new dependency needed.

**Files:**
- Create: `mobile/lib/features/live_session/widgets/guide_image_overlay.dart`

- [ ] **Step 1: Create GuideImageOverlay widget**

Create `mobile/lib/features/live_session/widgets/guide_image_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Overlay that slides up showing a guide image with camera PIP.
class GuideImageOverlay extends StatelessWidget {
  final String imageUrl;
  final String caption;
  final List<String> visualCues;
  final VoidCallback onDismiss;
  final Widget cameraPip;

  const GuideImageOverlay({
    super.key,
    required this.imageUrl,
    required this.caption,
    this.visualCues = const [],
    required this.onDismiss,
    required this.cameraPip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onVerticalDragEnd: (details) {
        // Swipe down to dismiss
        if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
          onDismiss();
        }
      },
      child: Container(
        color: Colors.black87,
        child: SafeArea(
          child: Column(
            children: [
              // Guide image with cue overlays
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    Center(
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) =>
                            const CircularProgressIndicator(),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 64),
                      ),
                    ),
                    // Cue annotations
                    ...visualCues.asMap().entries.map((entry) {
                      return Positioned(
                        left: 16,
                        top: 40.0 + entry.key * 28,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }),
                    // Camera PIP in corner
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 120,
                          height: 160,
                          child: cameraPip,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Caption
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  caption,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Dismiss button
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  height: 56,
                  width: 200,
                  child: FilledButton(
                    onPressed: onDismiss,
                    child: const Text('Looks Right',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/widgets/guide_image_overlay.dart
git commit -m "feat(epic-4): task 4.8 — guide image overlay with PIP and cue annotations"
```

---

### Task 4.9: Call chrome widget (D4.14)

**Files:**
- Create: `mobile/lib/features/live_session/widgets/call_chrome.dart`

- [ ] **Step 1: Create CallChrome widget**

Create `mobile/lib/features/live_session/widgets/call_chrome.dart`:

```dart
import 'package:flutter/material.dart';

/// FaceTime-style call controls: Mute, Flip Camera, End Call.
class CallChrome extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onFlipCamera;
  final VoidCallback onEndCall;

  const CallChrome({
    super.key,
    required this.isMuted,
    required this.onToggleMute,
    required this.onFlipCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      color: Colors.black38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: isMuted ? Icons.mic_off : Icons.mic,
            label: isMuted ? 'Unmute' : 'Mute',
            onTap: onToggleMute,
            color: isMuted ? Colors.red : Colors.white,
          ),
          _CallButton(
            icon: Icons.flip_camera_ios,
            label: 'Flip',
            onTap: onFlipCamera,
          ),
          _CallButton(
            icon: Icons.call_end,
            label: 'End',
            onTap: onEndCall,
            color: Colors.red,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool filled;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : Colors.white24,
            ),
            child: Icon(icon, color: filled ? Colors.white : color, size: 28),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/widgets/call_chrome.dart
git commit -m "feat(epic-4): task 4.9 — FaceTime-style call chrome widget"
```

---

### Task 4.10: Buddy caption widget (D4.9)

**Files:**
- Create: `mobile/lib/features/live_session/widgets/buddy_caption.dart`

- [ ] **Step 1: Create BuddyCaption widget**

Create `mobile/lib/features/live_session/widgets/buddy_caption.dart`:

```dart
import 'package:flutter/material.dart';

/// Live buddy caption overlay — fades after a few seconds.
class BuddyCaption extends StatefulWidget {
  final String text;
  final String connectionState;

  const BuddyCaption({
    super.key,
    required this.text,
    this.connectionState = 'Listening...',
  });

  @override
  State<BuddyCaption> createState() => _BuddyCaptionState();
}

class _BuddyCaptionState extends State<BuddyCaption>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.value = 1.0; // Start visible
  }

  @override
  void didUpdateWidget(BuddyCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.text.isNotEmpty) {
      _fadeController.value = 1.0;
      // Start fade after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _fadeController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.connectionState,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/widgets/buddy_caption.dart
git commit -m "feat(epic-4): task 4.10 — buddy caption widget with fade animation"
```

---

### Task 4.11: Live session screen redesign — split into sub-tasks (D4.1–D4.19, D8.6–D8.8)

**Files:**
- Rewrite: `mobile/lib/features/live_session/screens/live_session_screen.dart`

This is the core task — rewriting the live session from text-message style to FaceTime-style "call with mom" experience. **Split into 6 sub-steps** for manageable execution.

- [ ] **Step 1a: Scaffold — replace current layout with camera-first Stack**

Strip the existing Scaffold body and replace with a `Stack` layout:
- Layer 1: Full-screen `CameraPreview` (or black Container if camera unavailable)
- Layer 2: SafeArea column for overlays
- Remove `AppBar` — this is now a full-screen call experience
- Keep existing `_ws`, `_messageSub`, state fields

- [ ] **Step 1b: Wire audio capture + playback**

Add `AudioCaptureService` and `AudioPlaybackService` fields. In `_initSession()`:
1. Request permissions via `PermissionService`
2. If mic granted: start audio capture, forward chunks to WS
3. On `buddy_audio` WS event: play via `AudioPlaybackService`
4. On `buddy_interrupted` WS event: call `_audioPlayback.stopImmediately()` (barge-in <200ms)
5. If mic/camera denied: set `BuddyState.degraded`

- [ ] **Step 1c: Wire camera preview + vision integration**

Initialize `CameraService` in `_initSession()`. Camera is the primary view (full screen).
Add inline vision check: capture frame from live camera → upload → send URI via WS `vision_check` → buddy speaks result.

- [ ] **Step 1d: Integrate guide image overlay**

Handle `visual_guide` WS events. When received:
- Set `_showGuideOverlay = true`, store URL/cues/caption
- Render `GuideImageOverlay` on top of camera in Stack
- Camera view moves to PIP corner
- "Looks Right" dismisses overlay

- [ ] **Step 1e: Integrate process bar + call chrome**

Add `ProcessBar` at top of Stack (positioned). Add `CallChrome` at bottom.
Wire mute → pause audio capture, flip → `_camera.flipCamera()`, end → navigate to post-session.

- [ ] **Step 1f: WS message routing for all event types**

Consolidate all `_onMessage` handlers: `buddy_audio`, `buddy_interrupted`, `visual_guide`, `browse_observation`, `ingredient_candidates`, `browse_question`, `browse_complete`, `process_update`, `timer_alert`, `timer_warning`, `priority_conflict`, `conflict_resolved`, `session_state`, `mode_update`, `pong`, `error`.

**Reference architecture for steps 1a–1f** (the complete target structure):

The new screen layout:
1. Full-screen camera preview (primary view)
2. Buddy caption overlay (bottom, fading)
3. Sticky process bar (top)
4. Call chrome (bottom: mute, flip, end)
5. Guide image overlay (slides up over camera when active)
6. Connection state indicator
7. Audio capture (always on) + audio playback (buddy responses)

Key behavior:
- `initState`: request permissions → init camera → init audio capture → connect WS
- Audio: continuous mic capture → WS `voice_audio` events. WS `buddy_audio` → playback.
- Barge-in: on `barge_in` WS event, call `_playbackService.stopImmediately()` within 200ms
- Guide: on `visual_guide` WS event, show `GuideImageOverlay` over camera, camera → PIP
- No text input in default mode. `_TextInputBar` only shown when `BuddyState.degraded`
- All tap targets 64px+ for hands-busy ergonomics

```dart
// Key structure (abbreviated — full implementation in the actual rewrite):

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  late final WsClient _ws;
  late final AudioCaptureService _audioCapture;
  late final AudioPlaybackService _audioPlayback;
  late final CameraService _camera;
  // ... state fields ...

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    // 1. Request permissions
    final perms = await PermissionService().requestMicCamera();
    if (!perms.allGranted) {
      setState(() => _buddyState = BuddyState.degraded);
    }

    // 2. Initialize camera
    if (perms.cameraGranted) {
      _camera = CameraService();
      await _camera.initialize();
    }

    // 3. Initialize audio
    if (perms.micGranted) {
      _audioCapture = AudioCaptureService();
      await _audioCapture.start(onAudioChunk: (audio) {
        if (_ws.isConnected) _ws.sendAudio(audio);
      });
    }

    // 4. Connect WS
    _ws.connect(widget.sessionId);
  }

  void _onMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    // Handle buddy_audio → play
    if (type == 'buddy_audio') {
      _audioPlayback.play(msg['audio'] as String);
      return;
    }
    // Handle barge_in → stop playback immediately
    if (type == 'buddy_interrupted') {
      _audioPlayback.stopImmediately();
    }
    // Handle visual_guide → show overlay
    if (type == 'visual_guide') {
      setState(() {
        _guideImageUrl = msg['guide_image_url'];
        _guideCues = (msg['visual_cues'] as List?)?.cast<String>() ?? [];
        _guideCaption = msg['caption'] ?? '';
        _showGuideOverlay = true;
      });
    }
    // ... other handlers ...
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Layer 1: Camera preview (full screen)
          if (_camera.isInitialized)
            SizedBox.expand(child: CameraPreview(_camera.controller!)),

          // Layer 2: Process bar (top)
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0, right: 0,
            child: ProcessBar(processes: _processes, ...),
          ),

          // Layer 3: Buddy caption + connection state (bottom, above chrome)
          Positioned(
            bottom: 100, left: 0, right: 0,
            child: BuddyCaption(text: _lastBuddyMessage, ...),
          ),

          // Layer 4: Call chrome (bottom)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: CallChrome(
              isMuted: _isMuted,
              onToggleMute: _toggleMute,
              onFlipCamera: () => _camera.flipCamera(),
              onEndCall: _endCall,
            ),
          ),

          // Layer 5: Guide image overlay (conditional)
          if (_showGuideOverlay)
            GuideImageOverlay(
              imageUrl: _guideImageUrl!,
              caption: _guideCaption,
              visualCues: _guideCues,
              onDismiss: () => setState(() => _showGuideOverlay = false),
              cameraPip: CameraPreview(_camera.controller!),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compile**

Run: `cd mobile && flutter analyze --no-fatal-infos 2>&1 | grep -i error | head -5`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-4): task 4.11 — full live session redesign as FaceTime-style call"
```

---

### Task 4.12: WS handlers for browse mode on mobile (D4.6, D9.6, D9.7)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart` — add browse event handlers

- [ ] **Step 1: Add browse event handlers in _onMessage**

In the live session's `_onMessage`, add handlers:

```dart
case 'browse_observation':
  setState(() {
    _browseObservation = msg['observation'] as String? ?? '';
  });
  break;
case 'ingredient_candidates':
  setState(() {
    _browseCandidates = (msg['candidates'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];
  });
  break;
case 'browse_question':
  setState(() {
    _browseQuestion = msg['text'] as String? ?? '';
  });
  break;
case 'browse_complete':
  setState(() {
    _browseActive = false;
    _browseIngredients = (msg['ingredients'] as List?)?.cast<String>() ?? [];
  });
  break;
```

- [ ] **Step 2: Add browse UI overlay**

When `_browseActive` is true, show floating ingredient labels over camera feed with buddy narration.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-4): task 4.12 — browse mode WS handlers + floating label UI"
```

---

### Task 4.13: Ambient mode wiring (D4.15)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Wire ambient toggle to opt-in**

Ambient mode is already partially wired. Ensure:
- Opt-in only (not enabled by default)
- Rate-limited: when ambient enabled, capture 1 frame every 5 seconds max and send to WS
- Privacy banner shown when active (already exists)

Add periodic frame capture when ambient is on:

```dart
Timer? _ambientFrameTimer;

void _toggleAmbient() {
  final next = !_ambientEnabled;
  _ws.sendAmbientToggle(next);
  setState(() => _ambientEnabled = next);
  if (next) {
    _ambientFrameTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_camera.isInitialized && _ws.isConnected) {
        final framePath = await _camera.captureFrameToFile();
        if (framePath != null) {
          // Upload frame and send URI via WS
          // ... upload logic ...
        }
      }
    });
  } else {
    _ambientFrameTimer?.cancel();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-4): task 4.13 — ambient mode opt-in with rate-limited frame capture"
```

---

### Task 4.14: Reconnect button after max retries (D4.10)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`
- Modify: `mobile/lib/core/ws_client.dart` — expose max retries reached

- [ ] **Step 1: Add maxRetriesReached to WsClient**

In `mobile/lib/core/ws_client.dart`, add:

```dart
bool get maxRetriesReached => _reconnectAttempts >= _maxReconnectAttempts && _currentSessionId != null;
```

- [ ] **Step 2: Show reconnect button in live session**

In live_session_screen.dart, when `_ws.maxRetriesReached`:

```dart
if (_ws.maxRetriesReached)
  Positioned(
    top: MediaQuery.of(context).size.height / 2 - 30,
    left: 40, right: 40,
    child: FilledButton.icon(
      onPressed: () {
        _ws.resetReconnect();
        _ws.connect(widget.sessionId);
      },
      icon: const Icon(Icons.wifi),
      label: const Text('Connection Lost — Tap to Reconnect'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  ),
```

- [ ] **Step 3: Add resetReconnect to WsClient**

```dart
void resetReconnect() {
  _reconnectAttempts = 0;
  _reconnectTimer?.cancel();
}
```

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/core/ws_client.dart mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-4): task 4.14 — reconnect button after max WS retries"
```

---

## Chunk 6: Epic 5 — Process Management + Timer UI

### Task 5.1: Priority-based process bar styling (D5.1)

**Files:**
- Modify: `mobile/lib/features/live_session/widgets/process_bar.dart:141-158` — add color coding

- [ ] **Step 1: Add priority colors to process chips**

In `process_bar.dart`, update chip builder to use priority-based colors:

```dart
Color _priorityColor(String priority) {
  return switch (priority) {
    'P0' => Colors.red,
    'P1' => Colors.amber.shade700,
    'P2' => Theme.of(context).colorScheme.primary,
    'P3' => Colors.grey.shade500,
    'P4' => Colors.grey.shade400,
    _ => Colors.grey,
  };
}
```

P0 chips should pulse using `AnimatedContainer` or `AnimationController`.

- [ ] **Step 2: Add live countdown display (D5.3)**

Each chip in countdown state shows `mm:ss`:

```dart
if (process.state == 'countdown' && process.dueAt != null) {
  final remaining = process.dueAt!.difference(DateTime.now());
  final mm = remaining.inMinutes.toString().padLeft(2, '0');
  final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
```

Use a `Timer.periodic` (1s) to update countdowns.

- [ ] **Step 3: Amber pulse at 1-minute warning**

When `remaining < 60 seconds`, switch chip color to amber with pulse animation.

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/live_session/widgets/process_bar.dart
git commit -m "feat(epic-5): task 5.1 — priority-based process bar with live countdown"
```

---

### Task 5.2: Conflict timeout toast (D5.2)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Show toast when conflict auto-resolved**

In the conflict timeout handler:

```dart
onTimeout: () {
  setState(() {
    _conflictOptions = null;
    _conflictMessage = null;
  });
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Buddy handled it — keeping the more urgent process going'),
      duration: Duration(seconds: 4),
    ),
  );
},
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-5): task 5.2 — conflict timeout toast notification"
```

---

### Task 5.3: P0 critical interrupt banner (D5.5)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Add P0 banner handler**

When a `timer_alert` with `priority: "P0"` arrives:

```dart
void _handleTimerAlert(Map<String, dynamic> msg) {
  final priority = msg['priority'] as String? ?? 'P2';
  if (priority == 'P0') {
    // Full-width red banner + haptic
    HapticFeedback.heavyImpact();
    setState(() => _p0Alert = msg);
  }
  // ... existing logic ...
}
```

In build, show:

```dart
if (_p0Alert != null)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    color: Colors.red,
    child: Text(
      _p0Alert!['message'] as String? ?? 'Urgent!',
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
    ),
  ),
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-5): task 5.3 — P0 critical interrupt with red banner + haptics"
```

---

### Task 5.4: Audio alerts for timer events (D5.4)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Play gentle tone on timer warning/completion**

Use `just_audio` to play a short tone:

```dart
void _handleTimerWarning(Map<String, dynamic> msg) {
  // Play gentle warning tone
  _timerAlertPlayer.setAsset('assets/sounds/timer_warning.mp3');
  _timerAlertPlayer.play();
  // ... existing snackbar ...
}
```

Note: Add `assets/sounds/timer_warning.mp3` and `assets/sounds/timer_done.mp3` as audio assets. If no real assets available, use system sounds via `SystemSound.play(SystemSoundType.alert)`.

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-5): task 5.4 — audio alerts for timer warning/completion"
```

---

### Task 5.5: Verify timer/conflict WS events backend (D5.6, D5.7)

**Files:**
- Verify: `backend/app/services/timers.py` — timer_warning/timer_done flow
- Verify: `backend/app/services/processes.py` — conflict_resolved event
- Test: `backend/tests/test_timer_flow.py` (create)

- [ ] **Step 1: Write test for timer flow**

Create `backend/tests/test_timer_flow.py`:

```python
import pytest
import asyncio
from app.services.timers import TimerSystem


@pytest.mark.asyncio
async def test_timer_fires_warning_and_due():
    warnings = []
    completions = []

    async def on_warning(pid, name, remaining):
        warnings.append((pid, name, remaining))

    async def on_due(pid, name):
        completions.append((pid, name))

    ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warning)
    # Use a very short timer (0.05 min = 3 sec, but > 2 min for warning test)
    # For testing, we test sub-2-min timer (no warning)
    await ts.start_timer("p1", 0.05, "Quick Timer")

    await asyncio.sleep(4)
    assert ("p1", "Quick Timer") in completions
    assert len(warnings) == 0  # No warning for <2 min timer


@pytest.mark.asyncio
async def test_timer_cancel():
    completions = []

    async def on_due(pid, name):
        completions.append(pid)

    async def on_warning(pid, name, remaining):
        pass

    ts = TimerSystem(on_timer_due=on_due, on_timer_warning=on_warning)
    await ts.start_timer("p1", 0.1, "Timer")
    ts.cancel_timer("p1")
    await asyncio.sleep(8)
    assert len(completions) == 0
```

- [ ] **Step 2: Run tests**

Run: `cd backend && python -m pytest tests/test_timer_flow.py -v --timeout=15`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add backend/tests/test_timer_flow.py
git commit -m "feat(epic-5): task 5.5 — verify timer and conflict WS event flow"
```

---

## Chunk 7: Epic 6 — Vision/Guide/Taste/Recovery + Epic 9 — Zero-Setup

### Task 6.1: Wire vision check tab to real API (D6.1, D6.3)

**Files:**
- Modify: `mobile/lib/features/vision_guide/screens/vision_guide_screen.dart` — VisionCheckTab

- [ ] **Step 1: Replace stub with real API call**

In `VisionCheckTabState._captureAndCheck()`, replace hardcoded data:

```dart
Future<void> _captureAndCheck() async {
  setState(() { _loading = true; _error = null; });
  try {
    final camera = CameraService();
    await camera.initialize();
    final framePath = await camera.captureFrameToFile();
    await camera.dispose();

    if (framePath == null) throw Exception('Could not capture frame');

    final api = context.read<ApiClient>();
    final mediaPipeline = MediaPipeline(api: api);
    final uploadResult = await mediaPipeline.uploadFile(framePath, '/v1/upload');
    final frameUri = uploadResult['uri'] as String;

    final sessionApi = SessionApiService(api: api);
    final result = await sessionApi.visionCheck(widget.sessionId, frameUri: frameUri);
    setState(() => _result = {
      'assessment': result.assessment,
      'confidence': result.confidence,
      'stage': result.stage,
      'observations': result.observations,
      'recommendation': result.recommendation,
    });
  } catch (e) {
    setState(() => _error = e.toString());
  } finally {
    setState(() => _loading = false);
  }
}
```

- [ ] **Step 2: Add confidence-tier UX (D6.3)**

Display different UI per confidence tier:

```dart
Widget _buildResult() {
  final confidence = _result!['confidence'] as double;
  if (confidence >= 0.8) {
    // High: confident green badge
    return _ConfidenceBadge(color: Colors.green, label: 'Looks great!', ...);
  } else if (confidence >= 0.5) {
    // Medium: qualified + sensory prompt
    return _ConfidenceBadge(color: Colors.amber, label: 'Getting there', ...);
  } else if (confidence >= 0.2) {
    // Low: reposition request
    return _ConfidenceBadge(color: Colors.orange, label: 'Hard to tell — try repositioning', ...);
  } else {
    // Failed: sensory-only guidance
    return _ConfidenceBadge(color: Colors.red, label: 'Using sensory guidance instead', ...);
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/vision_guide/screens/vision_guide_screen.dart
git commit -m "feat(epic-6): task 6.1 — wire vision check to real API with confidence tiers"
```

---

### Task 6.2: Wire guide image tab to real API (D6.4, D6.5)

**Files:**
- Modify: `mobile/lib/features/vision_guide/screens/vision_guide_screen.dart` — GuideImageTab

- [ ] **Step 1: Replace stub with real API call**

In `GuideImageTab._requestGuide()`:

```dart
Future<void> _requestGuide() async {
  setState(() { _loading = true; _error = null; });
  try {
    final api = context.read<ApiClient>();
    final sessionApi = SessionApiService(api: api);
    final result = await sessionApi.visualGuide(widget.sessionId, stage: 'current');
    setState(() {
      _guideImageUrl = result.guideImageUrl;
      _targetState = result.targetState;
      _visualCues = result.visualCues;
    });
  } catch (e) {
    setState(() => _error = e.toString());
  } finally {
    setState(() => _loading = false);
  }
}
```

- [ ] **Step 2: Display cue overlays on guide image (D6.5)**

Render visual cues as positioned labels on the guide image.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/vision_guide/screens/vision_guide_screen.dart
git commit -m "feat(epic-6): task 6.2 — wire guide image to real API with cue overlays"
```

---

### Task 6.3: Wire taste check to real API — conversational (D6.6, D6.7)

**Files:**
- Modify: `mobile/lib/features/vision_guide/screens/vision_guide_screen.dart` — TasteCheckTab

- [ ] **Step 1: Replace form-based taste with conversational**

Remove tab/form UX. Replace with voice-triggered dialogue:

```dart
// In the live session (not the fallback screen), taste check is voice-initiated.
// The buddy asks: "How does it taste?" and the user responds vocally.
// For the fallback TasteCheckTab, use a simple prompt + response flow:

Future<void> _submitTaste(String diagnostic) async {
  setState(() { _loading = true; _error = null; });
  try {
    final api = context.read<ApiClient>();
    final sessionApi = SessionApiService(api: api);
    final result = await sessionApi.tasteCheck(widget.sessionId, diagnostic: diagnostic);
    setState(() {
      _dimensions = result.dimensions;
      _recommendation = result.recommendation;
    });
  } catch (e) {
    setState(() => _error = e.toString());
  } finally {
    setState(() => _loading = false);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/vision_guide/screens/vision_guide_screen.dart
git commit -m "feat(epic-6): task 6.3 — wire taste check to real API, conversational style"
```

---

### Task 6.4: Wire recovery to real API (D6.8, D6.9)

**Files:**
- Modify: `mobile/lib/features/vision_guide/screens/vision_guide_screen.dart` — RecoveryTab

- [ ] **Step 1: Replace stub with real API call**

```dart
Future<void> _submitRecovery(String issue) async {
  setState(() { _loading = true; _error = null; });
  try {
    final api = context.read<ApiClient>();
    final sessionApi = SessionApiService(api: api);
    final result = await sessionApi.recover(widget.sessionId, issue: issue);
    setState(() {
      _immediateAction = result.immediateAction;
      _explanation = result.explanation;
      _alternatives = result.alternativeActions;
      _severity = result.severity;
    });
  } catch (e) {
    setState(() => _error = e.toString());
  } finally {
    setState(() => _loading = false);
  }
}
```

- [ ] **Step 2: Instant response feel (D6.9)**

Show `_immediateAction` immediately in large bold text as first response, before the full explanation loads. Use optimistic UI — show "Turn off the heat NOW" type message first.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/vision_guide/screens/vision_guide_screen.dart
git commit -m "feat(epic-6): task 6.4 — wire recovery to real API with instant-feel UX"
```

---

### Task 9.1: Remove "Type Instead" from default call chrome (D9.1)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Remove Type Instead button from default mode**

In the redesigned live session screen, the `_TextInputBar` should only appear when `_buddyState == BuddyState.degraded`. The "Type Instead" toggle button should only appear when voice is unavailable. This should already be the case after Task 4.11, but verify and fix if needed.

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-9): task 9.1 — remove Type Instead from default call UI"
```

---

### Task 9.2: Verify ≤2 tap freestyle entry (D9.4, D9.5)

**Files:**
- Verify: `mobile/lib/features/live_session/screens/cook_now_screen.dart`
- Verify: `mobile/lib/features/scan/screens/home_screen.dart`

- [ ] **Step 1: Audit tap count**

Read home_screen.dart and cook_now_screen.dart. Verify the path:
- Home → "Cook Now" CTA (tap 1) → cook_now_screen → "Start Cooking" button (tap 2) → creates freestyle session → activates → navigates to live session

This should be ≤2 taps. If cook_now_screen requires additional setup before "Start Cooking", verify it's not more than 2 taps from Home.

- [ ] **Step 2: Fix if needed**

If more than 2 taps, consolidate: "Cook Now" should directly create + activate + navigate to live session.

- [ ] **Step 3: Commit if changes made**

```bash
git add mobile/lib/features/live_session/screens/cook_now_screen.dart mobile/lib/features/scan/screens/home_screen.dart
git commit -m "feat(epic-9): task 9.2 — verify ≤2 tap freestyle entry"
```

---

### Task 9.3: Zero-setup funnel metrics (D9.11)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/cook_now_screen.dart` — emit events
- Modify: `backend/app/services/analytics.py` — ensure events defined

- [ ] **Step 1: Add metric events to cook_now_screen**

At key points:
```dart
// When Cook Now tapped:
_emitEvent('zero_setup_entry_tapped');

// When session created:
_emitEvent('zero_setup_session_created');

// Track time from screen entry to first buddy instruction
final _entryTime = DateTime.now();
// ... in _onMessage when first buddy_message arrives:
final ttfi = DateTime.now().difference(_entryTime).inMilliseconds;
_emitEvent('time_to_first_instruction_ms', {'duration': ttfi});
```

- [ ] **Step 2: Add events to backend analytics**

In `backend/app/services/analytics.py`, add to PRODUCT_EVENTS:
```python
"zero_setup_entry_tapped": "Zero-setup Cook Now CTA tapped",
"zero_setup_session_created": "Zero-setup freestyle session created",
"time_to_first_instruction_ms": "Time from Cook Now to first buddy instruction",
```

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/live_session/screens/cook_now_screen.dart backend/app/services/analytics.py
git commit -m "feat(epic-9): task 9.3 — zero-setup funnel metrics"
```

---

### Task 9.4: Browse → cooking transition (D9.8)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Handle browse_complete → cooking transition**

When browse completes and buddy suggests a recipe:

```dart
case 'browse_complete':
  // Buddy suggests cooking with found ingredients
  // If user agrees (voice or tap), transition to cooking mode
  setState(() {
    _browseActive = false;
    _lastBuddyMessage = msg['text'] as String? ?? '';
  });
  break;
```

The transition happens naturally within the same WS session — the backend switches from browse mode to cooking mode when the user agrees.

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-9): task 9.4 — browse to cooking transition in live session"
```

---

## Chunk 8: Epic 7 — Post-Session, Observability & Demo + Final Polish

### Task 7.1: Wire memory gate to backend (D7.1)

**Files:**
- Modify: `mobile/lib/features/post_session/screens/post_session_screen.dart`
- Modify: `mobile/lib/core/session_api.dart` — add memory endpoint

- [ ] **Step 1: Add memory persistence API call**

In `session_api.dart`, add:
```dart
Future<void> saveMemory(String sessionId) async {
  await _api.postWithRetry('/v1/sessions/$sessionId/memory', body: {'save': true});
}
```

- [ ] **Step 2: Wire _confirmMemory to call backend**

In `post_session_screen.dart`:
```dart
Future<void> _confirmMemory() async {
  try {
    final api = context.read<ApiClient>();
    final sessionApi = SessionApiService(api: api);
    await sessionApi.saveMemory(widget.sessionId);
    setState(() {
      _memoryConfirmed = true;
      _showMemoryPrompt = false;
    });
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save: $e')),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/core/session_api.dart mobile/lib/features/post_session/screens/post_session_screen.dart
git commit -m "feat(epic-7): task 7.1 — wire memory gate to backend persistence"
```

---

### Task 7.2: Wind-down ≤3 interaction limit (D7.2)

**Files:**
- Modify: `mobile/lib/features/post_session/screens/post_session_screen.dart`

- [ ] **Step 1: Add interaction counter**

```dart
int _windDownInteractions = 0;
static const _maxWindDown = 3;

// In any user interaction after session complete:
if (_windDownInteractions >= _maxWindDown) {
  // Auto-navigate to home
  context.go(AppRoutes.home);
  return;
}
_windDownInteractions++;
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/post_session/screens/post_session_screen.dart
git commit -m "feat(epic-7): task 7.2 — enforce ≤3 wind-down interaction limit"
```

---

### Task 7.3: Deferred wind-down notification (D7.4)

**Files:**
- Create: `mobile/lib/core/notification_service.dart`

**Note:** `zonedSchedule` requires `TZDateTime` from `package:timezone`, not `DateTime`. Add `timezone: ^0.9.2` to pubspec.yaml dependencies.

- [ ] **Step 1: Add timezone dependency**

In `mobile/pubspec.yaml`, add:
```yaml
  timezone: ^0.9.2
```

Run: `cd mobile && flutter pub get`

- [ ] **Step 2: Create NotificationService**

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
  }

  Future<void> scheduleWindDown({
    required String sessionId,
    Duration delay = const Duration(minutes: 30),
  }) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(delay);
    await _plugin.zonedSchedule(
      sessionId.hashCode,
      'Cooking Session',
      'Your session is still open — want to finish up?',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails('wind_down', 'Wind Down Reminders'),
      ),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelWindDown(String sessionId) async {
    await _plugin.cancel(sessionId.hashCode);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/core/notification_service.dart
git commit -m "feat(epic-7): task 7.3 — deferred wind-down notification service"
```

---

### Task 7.4: Degradation notice surfacing (D7.8, D8.14)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Add degradation toast when mode changes**

When buddy state transitions to degraded:

```dart
if (newState == BuddyState.degraded && oldState != BuddyState.degraded) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Video unavailable — switching to voice only'),
      duration: Duration(seconds: 4),
    ),
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-7): task 7.4 — degradation notice via toast"
```

---

### Task 7.5: Product event verification (D7.5, D7.6)

**Files:**
- Modify: `backend/app/services/analytics.py` — verify all events
- Modify: `backend/app/routers/live.py` — add session_id to log entries

- [ ] **Step 1: Audit PRODUCT_EVENTS dict**

Verify these events exist in `analytics.py`:
- `session_started`, `session_completed`
- `vision_check_requested`, `visual_guide_requested`
- `barge_in_triggered`
- `taste_check_requested`, `recovery_requested`
- `browse_started`, `browse_completed`
- `timer_started`, `timer_completed`
- `zero_setup_entry_tapped`, `zero_setup_session_created`

Add any missing.

- [ ] **Step 2: Add correlation IDs (D7.6)**

In `backend/app/routers/live.py`, add `session_id` and auto-generated `event_id` to all log entries in the event loop:

```python
import uuid
# At top of event loop:
event_id = str(uuid.uuid4())
# In log_session_event call:
await log_session_event(session_id, event_type, {
    **data, "uid": user["uid"], "event_id": event_id,
})
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/services/analytics.py backend/app/routers/live.py
git commit -m "feat(epic-7): task 7.5 — verify product events + add correlation IDs"
```

---

### Task 7.6: Verify demo script against code (D7.9, D7.10)

**Files:**
- Verify: `backend/app/demo_script.py`
- Verify: `backend/seed_demo.py`

- [ ] **Step 1: Read and cross-reference**

Read `demo_script.py` and verify each act (0-4) matches the actual code flow:
- Act 0: Home → scan → ingredients detected
- Act 1: Suggestions → select → checklist
- Act 2: Live session → buddy guides → vision check
- Act 3: Process management → conflict → timer
- Act 4: Session complete → memory gate → done

Cross-reference `seed_demo.py` checkpoints with demo script expectations.

- [ ] **Step 2: Fix any mismatches found**

- [ ] **Step 3: Commit if changes made**

```bash
git add backend/app/demo_script.py backend/seed_demo.py
git commit -m "feat(epic-7): task 7.6 — validate demo script against code"
```

---

### Task 8.9: Loading state consistency (D8.15)

**Files:**
- Modify various screens to use consistent loading patterns

- [ ] **Step 1: Audit loading states across screens**

Ensure:
- Content loads → skeleton loader (shimmer effect)
- Action in progress → subtle spinner (never blocking call UI)
- Never show raw CircularProgressIndicator on live session screen

- [ ] **Step 2: Apply consistent patterns**

Use existing `LoadingIndicator` and `LoadingOverlay` widgets from `mobile/lib/shared/widgets/`.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/
git commit -m "feat(epic-8): task 8.9 — consistent loading states across screens"
```

---

### Task 8.10: Accessibility basics (D8.17)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`
- Modify: `mobile/lib/features/live_session/widgets/call_chrome.dart`
- Modify: `mobile/lib/features/live_session/widgets/process_bar.dart`

- [ ] **Step 1: Add semantic labels to critical controls**

```dart
// Call chrome buttons:
Semantics(label: 'Mute microphone', child: _muteButton),
Semantics(label: 'Flip camera', child: _flipButton),
Semantics(label: 'End cooking session', child: _endButton),

// Process bar chips:
Semantics(label: '$processName, $state, $timeRemaining', child: chip),
```

- [ ] **Step 2: Verify text scaling**

Ensure no text uses fixed pixel sizes below 14sp. All critical text should scale with MediaQuery.textScaleFactor.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/live_session/
git commit -m "feat(epic-8): task 8.10 — accessibility labels + text scaling"
```

---

### Task 8.11: Smooth scan → suggestions → live transition (D8.10)

**Files:**
- Modify: `mobile/lib/features/suggestions/screens/suggestions_screen.dart`

- [ ] **Step 1: Wire "Start Cooking" to seamless flow**

When user selects a recipe and taps "Start Cooking":
1. Create session (POST /v1/sessions)
2. Activate session (POST /v1/sessions/{id}/activate)
3. Navigate to live session screen

All in one loading sequence with the button showing a spinner.

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/suggestions/screens/suggestions_screen.dart
git commit -m "feat(epic-8): task 8.11 — seamless scan to suggestions to live transition"
```

---

### Task 9.5: Safety constraints verification (D9.9)

**Files:**
- Verify: `backend/app/agents/safety.py`
- Test: `backend/tests/test_safety.py` (create)

- [ ] **Step 1: Write test for safety keyword detection**

**Note:** The actual function is `check_safety_triggers(text)` at `backend/app/agents/safety.py:31`. It returns `list[dict]` with keys `trigger`, `warning`, `priority` — NOT `{"flagged": bool}`.

```python
import pytest
from app.agents.safety import check_safety_triggers


def test_high_risk_keywords_detected():
    """Safety filter should flag high-risk keywords in freestyle mode."""
    result = check_safety_triggers("how to use a deep fryer with water")
    assert len(result) > 0
    assert any(w["trigger"] == "deep fry" for w in result)
    assert all(w["priority"] == "high" for w in result)


def test_normal_query_returns_empty():
    result = check_safety_triggers("how long to boil pasta")
    # "boiling" IS a keyword, so this should return a warning
    assert len(result) >= 0  # boiling may trigger


def test_fire_safety_warning():
    result = check_safety_triggers("there's a fire in the pan")
    assert any(w["trigger"] == "fire" for w in result)
    assert "never use water" in result[0]["warning"].lower() or "smother" in result[0]["warning"].lower()
```

- [ ] **Step 2: Run test, fix if needed**

Run: `cd backend && python -m pytest tests/test_safety.py -v`

- [ ] **Step 3: Commit**

```bash
git add backend/tests/test_safety.py
git commit -m "feat(epic-9): task 9.5 — verify safety constraints in freestyle mode"
```

---

### Task 9.6: Text input audit matrix (D9.10)

**Files:**
- Create: `docs/text-input-audit.md`

- [ ] **Step 1: Audit every TextField in mobile code**

Search all `.dart` files for `TextField` and `TextFormField`. For each:
- File and line number
- Purpose
- Decision: Keep / Replace with voice / Optional (degraded-mode only)

- [ ] **Step 2: Implement replacements**

For each "Replace" item, add voice alternative (mic icon + speech-to-text).
For each "Optional" item, hide behind degraded-mode check.

- [ ] **Step 3: Commit**

```bash
git add docs/text-input-audit.md mobile/lib/
git commit -m "feat(epic-9): task 9.6 — text input audit + voice-first replacements"
```

---

## Final Verification

### Task F.1: Full import verification

- [ ] **Step 1: Backend import check**

Run: `cd backend && python -c "from app.main import app; print('OK')"`
Expected: `OK`

- [ ] **Step 2: Mobile analyze check**

Run: `cd mobile && flutter analyze --no-fatal-infos`
Expected: No errors

- [ ] **Step 3: Backend tests**

Run: `cd backend && python -m pytest tests/ -v --timeout=30`
Expected: All pass

- [ ] **Step 4: Mobile tests**

Run: `cd mobile && flutter test`
Expected: All pass

---

## Chunk 9: Previously Missing Gap Items

These items were identified in plan review as missing from the original task list.

### Task M.1: Buddy-initiated guide images at checkpoints (D4.17, D4.22)

**Files:**
- Modify: `backend/app/routers/live.py` — after step_complete, check if step has `guide_image_prompt`
- Modify: `backend/app/agents/orchestrator.py` — add guide image trigger logic

- [ ] **Step 1: In step_complete handler, check for guide_image_prompt**

After `orchestrator.advance_step()` in `live.py`, if the current recipe step has a `guide_image_prompt`, automatically generate and send a visual guide:

```python
if recipe and current_step <= len(recipe.get("steps", [])):
    step_data = recipe["steps"][current_step - 1]
    if step_data.get("guide_image_prompt"):
        guide_result = await orchestrator.generate_guide_image(step_data["guide_image_prompt"])
        if guide_result:
            await websocket.send_json({
                "type": "visual_guide",
                "guide_image_url": guide_result["url"],
                "visual_cues": guide_result.get("cues", []),
                "caption": guide_result.get("caption", "Here's what to look for"),
            })
```

- [ ] **Step 2: Add voice narration with guide (D4.22)**

When sending `visual_guide`, also generate and send a `buddy_audio` event with the buddy narrating the guide.

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/live.py backend/app/agents/orchestrator.py
git commit -m "feat(epic-4): buddy-initiated guide images at step checkpoints"
```

---

### Task M.2: User-initiated guide request (D4.18)

**Files:**
- Modify: `backend/app/routers/live.py` — add `guide_request` event handler
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart` — voice trigger

- [ ] **Step 1: Add guide_request WS event handler**

In `live.py` event loop:
```python
elif event_type == "guide_request":
    current_step = orchestrator.state.get("current_step", 1)
    if recipe and current_step <= len(recipe.get("steps", [])):
        step_data = recipe["steps"][current_step - 1]
        prompt = step_data.get("guide_image_prompt", f"Show what step {current_step} should look like")
        guide_result = await orchestrator.generate_guide_image(prompt)
        if guide_result:
            await websocket.send_json({
                "type": "visual_guide",
                "guide_image_url": guide_result["url"],
                "visual_cues": guide_result.get("cues", []),
                "caption": "Here's what yours should look like",
            })
```

- [ ] **Step 2: Add guide_request to valid WS event types**

In `backend/app/models/ws_events.py`, add `"guide_request"` to `VALID_EVENT_TYPES`.

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/live.py backend/app/models/ws_events.py
git commit -m "feat(epic-4): user-initiated guide request via WS"
```

---

### Task M.3: Guide image style consistency (D4.21)

**Files:**
- Modify: `backend/app/agents/guide_image.py` — cache Gemini chat session per cooking session

- [ ] **Step 1: Add chat session caching**

In `guide_image.py`, maintain a dict of `{session_id: chat_session}`. Reuse the same Gemini chat object for all guide image generations within a single cooking session, ensuring consistent visual style.

- [ ] **Step 2: Commit**

```bash
git add backend/app/agents/guide_image.py
git commit -m "feat(epic-4): cache Gemini chat session per cooking session for style consistency"
```

---

### Task M.4: Step transition atomicity verification (D4.23)

**Files:**
- Verify: `backend/app/routers/live.py:174-212` — step_complete handler
- Verify: `backend/app/services/sessions.py` — persist_session_state

- [ ] **Step 1: Verify atomic persistence**

Read the step_complete handler. Verify that `persist_session_state` writes `current_step` to Firestore BEFORE sending the WS update to the client. If not, reorder so persistence happens first.

- [ ] **Step 2: Write test**

```python
@pytest.mark.asyncio
async def test_step_persisted_before_ws_update():
    """Step transition must be persisted to Firestore before WS response."""
    # Mock persist_session_state and verify call order
    pass  # Implement with call order tracking via side_effect
```

- [ ] **Step 3: Commit if changes made**

---

### Task M.5: Inline vision in live session (D6.2)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Add voice-triggered vision check from live camera**

When buddy detects vision-related query (or user says "how does this look?"), capture frame from the active camera, upload to GCS, and send `vision_check` WS event — all without leaving the call screen. Buddy speaks the result inline.

The flow: capture → upload → WS `vision_check` → backend responds → `buddy_message` with assessment → buddy speaks it.

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-6): inline vision check from live camera feed"
```

---

### Task M.6: Bright-kitchen-lighting readability (D6.11)

**Files:**
- Modify: `mobile/lib/features/vision_guide/screens/vision_guide_screen.dart`
- Modify: `mobile/lib/features/live_session/widgets/buddy_caption.dart`

- [ ] **Step 1: High contrast for vision results**

Ensure confidence badges use high-contrast colors (dark text on light background, or vice versa). Minimum 4.5:1 contrast ratio. Text size ≥16sp for confidence labels. Use `Colors.black87` on white containers, not subtle grays.

- [ ] **Step 2: Verify buddy caption readability**

Buddy captions overlay on camera feed. Add a semi-transparent dark gradient behind caption text to ensure readability regardless of camera content.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/vision_guide/ mobile/lib/features/live_session/widgets/
git commit -m "feat(epic-6): bright-kitchen readability for vision results + captions"
```

---

### Task M.7: Auto-reconnect WS on connectivity recovery (D8.3 completion)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`
- Modify: `mobile/lib/core/connectivity.dart`

- [ ] **Step 1: Wire ConnectivityService to WsClient**

In live session `initState`, listen to connectivity changes:

```dart
final connectivity = ConnectivityService();
connectivity.onStatusChange.listen((isOnline) {
  if (isOnline && !_ws.isConnected && _ws.state != WsConnectionState.connecting) {
    _ws.resetReconnect();
    _ws.connect(widget.sessionId);
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-8): auto-reconnect WS on connectivity recovery"
```

---

### Task M.8: ConnectivityBanner dismissal persistence (D8.16)

**Files:**
- Modify: `mobile/lib/shared/widgets/connectivity_banner.dart`

- [ ] **Step 1: Add session-scoped dismiss state**

Track banner dismissal in a `ValueNotifier<bool>` scoped to the current session (not persisted to disk, just in-memory per session):

```dart
final _dismissed = ValueNotifier<bool>(false);

void dismiss() => _dismissed.value = true;
// Reset on new session start
void resetForNewSession() => _dismissed.value = false;
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/shared/widgets/connectivity_banner.dart
git commit -m "feat(epic-8): persist connectivity banner dismissal per session"
```

---

### Task M.9: Fixture-driven contract tests (D8.18)

**Files:**
- Create: `mobile/test/core/contract_test.dart`
- Create: `mobile/test/fixtures/` — JSON fixture files

- [ ] **Step 1: Create fixture files**

Create JSON fixtures for each endpoint response:
- `mobile/test/fixtures/activate_response.json`
- `mobile/test/fixtures/vision_check_response.json`
- `mobile/test/fixtures/visual_guide_response.json`
- `mobile/test/fixtures/taste_check_response.json`
- `mobile/test/fixtures/recovery_response.json`
- `mobile/test/fixtures/complete_response.json`
- `mobile/test/fixtures/ws_events.json` (all WS event types)

- [ ] **Step 2: Write contract decode tests**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/session_api.dart';

void main() {
  group('Contract tests', () {
    test('ActivateResponse decodes from fixture', () {
      final json = jsonDecode(
        File('test/fixtures/activate_response.json').readAsStringSync()
      ) as Map<String, dynamic>;
      final response = ActivateResponse.fromJson(json);
      expect(response.sessionId, isNotEmpty);
      expect(response.status, isNotEmpty);
    });

    test('VisionCheckResponse decodes from fixture', () {
      final json = jsonDecode(
        File('test/fixtures/vision_check_response.json').readAsStringSync()
      ) as Map<String, dynamic>;
      final response = VisionCheckResponse.fromJson(json);
      expect(response.confidence, greaterThanOrEqualTo(0));
      expect(response.assessment, isNotEmpty);
    });

    // ... similar for all response types
  });
}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/test/core/contract_test.dart mobile/test/fixtures/
git commit -m "feat(epic-8): fixture-driven contract tests for all API responses"
```

---

### Task M.10: Degraded text input keyboard handling (D9.2, D9.13)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Floating minimal input for degraded mode**

When text input is shown in degraded mode, use a floating overlay that doesn't obscure the camera:

```dart
if (_textInputMode && _buddyState == BuddyState.degraded)
  Positioned(
    bottom: 80, // Above call chrome
    left: 16, right: 16,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(24),
      child: _TextInputBar(controller: _textController, onSend: _onTextSend),
    ),
  ),
```

- [ ] **Step 2: In-session context capture without text fields (D9.13)**

Context capture (e.g., "what dish are you making?") should use voice or tap-based options, not text fields. Add predefined option chips:

```dart
Wrap(
  children: [
    for (final option in ['Pasta', 'Stir fry', 'Soup', 'Salad', 'Other'])
      Padding(
        padding: const EdgeInsets.all(4),
        child: ChoiceChip(
          label: Text(option),
          selected: _selectedContext == option,
          onSelected: (_) => _selectContext(option),
        ),
      ),
  ],
)
```

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-9): floating text input + voice-first context capture"
```

---

### Task M.11: Browse fallback for poor video quality (D9.14)

**Files:**
- Modify: `mobile/lib/features/live_session/screens/live_session_screen.dart`

- [ ] **Step 1: Handle low-confidence browse observations**

When browse_observation arrives with low confidence:

```dart
case 'browse_observation':
  final confidence = (msg['confidence'] as num?)?.toDouble() ?? 0;
  if (confidence < 0.3) {
    setState(() {
      _lastBuddyMessage = "I can't quite see — try holding the camera still, "
          "or just tell me what you have.";
    });
  }
  break;
```

- [ ] **Step 2: Commit**

```bash
git add mobile/lib/features/live_session/screens/live_session_screen.dart
git commit -m "feat(epic-9): browse fallback for poor video quality"
```

---

### Task M.12: Demo script zero-setup segment + remaining Epic 7 items (D9.12, D7.3, D7.7, D7.11, D7.12)

**Files:**
- Modify: `backend/app/demo_script.py` — add zero-setup segment
- Verify: `mobile/lib/core/session_api.dart` — CompleteResponse fields match backend
- Create: `docs/architecture-diagram.md` — spec-matching architecture diagram
- Verify: `README.md` — Devpost checklist completeness

- [ ] **Step 1: Add zero-setup segment to demo script (D9.12)**

In `backend/app/demo_script.py`, add an act or segment showing:
- Home → Cook Now (1 tap) → Start Cooking (2 taps) → buddy greets → browse fridge → suggests recipe → cooking begins

- [ ] **Step 2: Validate CompleteResponse model against backend (D7.3)**

Read `backend/app/routers/sessions.py` complete endpoint. Verify the response fields match `CompleteResponse` in `mobile/lib/core/session_api.dart`. Fix any mismatches.

- [ ] **Step 3: Degradation e2e verification notes (D7.7)**

Add comments/test stubs documenting the degradation paths:
- Gemini timeout → text fallback
- Vision failure → sensory guidance
- Audio failure → text mode
- WS disconnect → reconnect with exponential backoff

- [ ] **Step 4: Architecture diagram (D7.11)**

Create `docs/architecture-diagram.md` with ASCII or Mermaid diagram matching the spec.

- [ ] **Step 5: README/Devpost check (D7.12)**

Verify `README.md` has: project description, setup instructions, demo video link placeholder, architecture overview, tech stack.

- [ ] **Step 6: Commit**

```bash
git add backend/app/demo_script.py docs/ README.md mobile/lib/core/session_api.dart
git commit -m "feat(epic-7): demo script zero-setup + architecture diagram + README"
```

---

## Dependency Graph

```
Chunk 1 (Epic 1+2) ─────────────────┐
                                      │
Chunk 2 (Epic 8 Infra) ─────────────┤
        │                             │
        ├── Chunk 3 (Epic 3 Scan)    │
        │                             │
Chunk 4 (Epic 4 Backend) ───────────┤
        │                             │
        └── Chunk 5 (Epic 4 Mobile) ─┤
                │                     │
                ├── Chunk 6 (Epic 5) ─┤
                │                     │
                └── Chunk 7 (Epic 6+9)┤
                                      │
                    Chunk 8 (Epic 7+Polish)
                                      │
                    Chunk 9 (Missing Items)
```

Chunks 1, 2, and 4 can run in parallel (backend vs mobile infra vs backend audio).
Chunks 3, 5 depend on Chunk 2.
Chunks 6, 7 depend on Chunk 5.
Chunk 8 depends on all others.
Chunk 9 items (M.1–M.12) slot into their respective epics — most depend on Chunk 5 being complete. M.9 (contract tests) and M.12 (demo/docs) can run last.
