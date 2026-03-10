# Text Input Audit Matrix (D9.10)

Voice-first design audit: every `TextField` / `TextFormField` in the mobile app.

## Verdict Key
- **KEEP**: Required for this feature, no voice alternative makes sense
- **HIDDEN**: Only shown as fallback when voice is unavailable
- **REPLACE**: Should be replaced with voice input in future iteration

## Auth Screens (keep — keyboard is the right UX here)

| File | Line | Purpose | Verdict |
|------|------|---------|---------|
| `login_screen.dart` | 172 | Email field | KEEP |
| `login_screen.dart` | 191 | Password field | KEEP |
| `signup_screen.dart` | 158 | Display name | KEEP |
| `signup_screen.dart` | 171 | Email field | KEEP |
| `signup_screen.dart` | 190 | Password field | KEEP |
| `signup_screen.dart` | 216 | Confirm password | KEEP |
| `forgot_password_screen.dart` | 158 | Email for reset | KEEP |
| `profile_screen.dart` | 101 | Display name edit dialog | KEEP |

## Recipe Management (keep — structured data entry)

| File | Line | Purpose | Verdict |
|------|------|---------|---------|
| `recipe_create_screen.dart` | 61 | Recipe title | KEEP |
| `recipe_create_screen.dart` | 71 | Recipe description | KEEP |
| `recipe_create_screen.dart` | 83 | Prep time | KEEP |
| `recipe_create_screen.dart` | 91 | Cook time | KEEP |
| `recipe_create_screen.dart` | 117 | Servings | KEEP |
| `recipe_create_screen.dart` | 328 | Ingredient name | KEEP |
| `recipe_create_screen.dart` | 341 | Ingredient amount | KEEP |
| `recipe_create_screen.dart` | 352 | Ingredient unit | KEEP |
| `recipe_create_screen.dart` | 401 | Step instruction | KEEP |
| `recipe_list_screen.dart` | 127 | Search/filter dialog | KEEP |

## Scan Flow

| File | Line | Purpose | Verdict |
|------|------|---------|---------|
| `ingredient_review_screen.dart` | 280 | Edit ingredient name | KEEP — quick correction of AI detection |

## Live Session (voice-first zone)

| File | Line | Purpose | Verdict |
|------|------|---------|---------|
| `live_session_screen.dart` | 936 | Text query fallback (degraded mode) | HIDDEN — only shown when mic permission denied |
| `cook_now_screen.dart` | 237 | Dish goal input ("What do you want to cook?") | REPLACE — should accept voice in future; currently OK for MVP |

## Vision Guide

| File | Line | Purpose | Verdict |
|------|------|---------|---------|
| `vision_guide_screen.dart` | 862 | Taste description input | REPLACE — natural voice input preferred in cooking context |
| `vision_guide_screen.dart` | 1164 | Recovery issue description | REPLACE — same rationale |

## Summary

- **12 KEEP**: Auth forms, recipe CRUD, ingredient correction, search — keyboard is appropriate
- **1 HIDDEN**: Live session text fallback — correctly gated behind degraded mode
- **3 REPLACE**: Cook-now goal, taste description, recovery description — candidates for voice-to-text in post-MVP

The live session screen has zero visible text inputs during the happy path (voice-first). Text input only appears when mic permission is denied, matching the voice-first design principle.
