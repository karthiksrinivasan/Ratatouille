/// Dart models mirroring the backend inventory Pydantic schemas.
library;

/// A single ingredient detected from fridge/pantry images.
class DetectedIngredient {
  final String name;
  final String nameNormalized;
  final double confidence;
  final int sourceImageIndex;

  const DetectedIngredient({
    required this.name,
    required this.nameNormalized,
    required this.confidence,
    this.sourceImageIndex = 0,
  });

  factory DetectedIngredient.fromJson(Map<String, dynamic> json) {
    return DetectedIngredient(
      name: json['name'] as String? ?? '',
      nameNormalized: json['name_normalized'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      sourceImageIndex: json['source_image_index'] as int? ?? 0,
    );
  }

  /// Confidence tier for UI display.
  ConfidenceTier get tier {
    if (confidence >= 0.8) return ConfidenceTier.high;
    if (confidence >= 0.5) return ConfidenceTier.medium;
    return ConfidenceTier.low;
  }
}

enum ConfidenceTier { high, medium, low }

/// Response from POST /v1/inventory-scans (scan creation).
class ScanCreateResponse {
  final String scanId;
  final String captureMode;
  final int imageCount;
  final String status;

  const ScanCreateResponse({
    required this.scanId,
    required this.captureMode,
    required this.imageCount,
    required this.status,
  });

  factory ScanCreateResponse.fromJson(Map<String, dynamic> json) {
    return ScanCreateResponse(
      scanId: json['scan_id'] as String? ?? '',
      captureMode: json['capture_mode'] as String? ?? 'images',
      imageCount: json['image_count'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
    );
  }
}

/// Response from POST /v1/inventory-scans/{id}/detect.
class DetectResponse {
  final String scanId;
  final List<DetectedIngredient> detectedIngredients;
  final String status;
  final int lowConfidenceCount;

  const DetectResponse({
    required this.scanId,
    required this.detectedIngredients,
    required this.status,
    required this.lowConfidenceCount,
  });

  factory DetectResponse.fromJson(Map<String, dynamic> json) {
    return DetectResponse(
      scanId: json['scan_id'] as String? ?? '',
      detectedIngredients: (json['detected_ingredients'] as List<dynamic>?)
              ?.map((e) =>
                  DetectedIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: json['status'] as String? ?? '',
      lowConfidenceCount: json['low_confidence_count'] as int? ?? 0,
    );
  }
}

/// Response from POST /v1/inventory-scans/{id}/confirm-ingredients.
class ConfirmResponse {
  final String scanId;
  final List<String> confirmedIngredients;
  final String status;

  const ConfirmResponse({
    required this.scanId,
    required this.confirmedIngredients,
    required this.status,
  });

  factory ConfirmResponse.fromJson(Map<String, dynamic> json) {
    return ConfirmResponse(
      scanId: json['scan_id'] as String? ?? '',
      confirmedIngredients:
          (json['confirmed_ingredients'] as List<dynamic>?)?.cast<String>() ??
              [],
      status: json['status'] as String? ?? '',
    );
  }
}

/// A recipe suggestion from the dual-lane endpoint.
class RecipeSuggestion {
  final String suggestionId;
  final String sourceType; // "saved_recipe" | "buddy_generated"
  final String? recipeId;
  final String title;
  final String? description;
  final double matchScore;
  final List<String> matchedIngredients;
  final List<String> missingIngredients;
  final int? estimatedTimeMin;
  final String? difficulty;
  final String? cuisine;
  final String sourceLabel; // "Saved" | "Buddy"
  final String explanation;
  final List<String> groundingSources;
  final List<String> assumptions;

  const RecipeSuggestion({
    required this.suggestionId,
    required this.sourceType,
    this.recipeId,
    required this.title,
    this.description,
    required this.matchScore,
    this.matchedIngredients = const [],
    this.missingIngredients = const [],
    this.estimatedTimeMin,
    this.difficulty,
    this.cuisine,
    required this.sourceLabel,
    this.explanation = '',
    this.groundingSources = const [],
    this.assumptions = const [],
  });

  factory RecipeSuggestion.fromJson(Map<String, dynamic> json) {
    return RecipeSuggestion(
      suggestionId: json['suggestion_id'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? '',
      recipeId: json['recipe_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      matchScore: (json['match_score'] as num?)?.toDouble() ?? 0.0,
      matchedIngredients:
          (json['matched_ingredients'] as List<dynamic>?)?.cast<String>() ??
              [],
      missingIngredients:
          (json['missing_ingredients'] as List<dynamic>?)?.cast<String>() ??
              [],
      estimatedTimeMin: json['estimated_time_min'] as int?,
      difficulty: json['difficulty'] as String?,
      cuisine: json['cuisine'] as String?,
      sourceLabel: json['source_label'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      groundingSources:
          (json['grounding_sources'] as List<dynamic>?)?.cast<String>() ?? [],
      assumptions:
          (json['assumptions'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  bool get isSaved => sourceType == 'saved_recipe';
  bool get isBuddy => sourceType == 'buddy_generated';

  int get matchPercent => (matchScore * 100).round();
}

/// Response from GET /v1/inventory-scans/{id}/suggestions.
class SuggestionsResponse {
  final String scanId;
  final List<RecipeSuggestion> fromSaved;
  final List<RecipeSuggestion> buddyRecipes;
  final int totalSuggestions;

  const SuggestionsResponse({
    required this.scanId,
    required this.fromSaved,
    required this.buddyRecipes,
    required this.totalSuggestions,
  });

  factory SuggestionsResponse.fromJson(Map<String, dynamic> json) {
    return SuggestionsResponse(
      scanId: json['scan_id'] as String? ?? '',
      fromSaved: (json['from_saved'] as List<dynamic>?)
              ?.map(
                  (e) => RecipeSuggestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      buddyRecipes: (json['buddy_recipes'] as List<dynamic>?)
              ?.map(
                  (e) => RecipeSuggestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalSuggestions: json['total_suggestions'] as int? ?? 0,
    );
  }
}

/// Response from GET /v1/inventory-scans/{id}/suggestions/{sid}/explain.
class ExplainResponse {
  final String suggestionId;
  final String title;
  final String explanationFull;
  final List<String> groundingSources;
  final List<String> matchedIngredients;
  final List<String> missingIngredients;
  final List<String> assumptions;
  final List<String> lowConfidenceWarnings;
  final double matchScore;

  const ExplainResponse({
    required this.suggestionId,
    required this.title,
    required this.explanationFull,
    this.groundingSources = const [],
    this.matchedIngredients = const [],
    this.missingIngredients = const [],
    this.assumptions = const [],
    this.lowConfidenceWarnings = const [],
    required this.matchScore,
  });

  factory ExplainResponse.fromJson(Map<String, dynamic> json) {
    return ExplainResponse(
      suggestionId: json['suggestion_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      explanationFull: json['explanation_full'] as String? ?? '',
      groundingSources:
          (json['grounding_sources'] as List<dynamic>?)?.cast<String>() ?? [],
      matchedIngredients:
          (json['matched_ingredients'] as List<dynamic>?)?.cast<String>() ?? [],
      missingIngredients:
          (json['missing_ingredients'] as List<dynamic>?)?.cast<String>() ?? [],
      assumptions:
          (json['assumptions'] as List<dynamic>?)?.cast<String>() ?? [],
      lowConfidenceWarnings:
          (json['low_confidence_warnings'] as List<dynamic>?)?.cast<String>() ??
              [],
      matchScore: (json['match_score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Response from POST /v1/inventory-scans/{id}/start-session.
class StartSessionResponse {
  final String recipeId;
  final String scanId;
  final String suggestionId;
  final String sessionId;
  final String sessionStatus;
  final String nextEndpoint;

  const StartSessionResponse({
    required this.recipeId,
    required this.scanId,
    required this.suggestionId,
    required this.sessionId,
    required this.sessionStatus,
    required this.nextEndpoint,
  });

  factory StartSessionResponse.fromJson(Map<String, dynamic> json) {
    final session = json['session'] as Map<String, dynamic>? ?? {};
    final next = json['next'] as Map<String, dynamic>? ?? {};
    return StartSessionResponse(
      recipeId: json['recipe_id'] as String? ?? '',
      scanId: json['scan_id'] as String? ?? '',
      suggestionId: json['suggestion_id'] as String? ?? '',
      sessionId: session['session_id'] as String? ?? '',
      sessionStatus: session['status'] as String? ?? '',
      nextEndpoint: next['endpoint'] as String? ?? '',
    );
  }
}
