/// Dart models mirroring the backend Recipe Pydantic schemas.
library;

class Ingredient {
  final String name;
  final String nameNormalized;
  final String? quantity;
  final String? unit;
  final String? preparation;
  final String? category;

  const Ingredient({
    required this.name,
    this.nameNormalized = '',
    this.quantity,
    this.unit,
    this.preparation,
    this.category,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String? ?? '',
      nameNormalized: json['name_normalized'] as String? ?? '',
      quantity: json['quantity'] as String?,
      unit: json['unit'] as String?,
      preparation: json['preparation'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'name_normalized': nameNormalized,
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (preparation != null) 'preparation': preparation,
        if (category != null) 'category': category,
      };

  /// Human-readable display string, e.g. "2 cups onion, diced".
  String get displayText {
    final parts = <String>[];
    if (quantity != null) parts.add(quantity!);
    if (unit != null) parts.add(unit!);
    parts.add(name);
    if (preparation != null) parts.add('($preparation)');
    return parts.join(' ');
  }
}

class RecipeStep {
  final int stepNumber;
  final String instruction;
  final List<String> techniqueTags;
  final double? durationMinutes;
  final bool isParallel;
  final String? referenceImageUri;
  final String? guideImagePrompt;

  const RecipeStep({
    required this.stepNumber,
    required this.instruction,
    this.techniqueTags = const [],
    this.durationMinutes,
    this.isParallel = false,
    this.referenceImageUri,
    this.guideImagePrompt,
  });

  factory RecipeStep.fromJson(Map<String, dynamic> json) {
    return RecipeStep(
      stepNumber: json['step_number'] as int? ?? 0,
      instruction: json['instruction'] as String? ?? '',
      techniqueTags: (json['technique_tags'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      durationMinutes: (json['duration_minutes'] as num?)?.toDouble(),
      isParallel: json['is_parallel'] as bool? ?? false,
      referenceImageUri: json['reference_image_uri'] as String?,
      guideImagePrompt: json['guide_image_prompt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'step_number': stepNumber,
        'instruction': instruction,
        'technique_tags': techniqueTags,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'is_parallel': isParallel,
        if (referenceImageUri != null) 'reference_image_uri': referenceImageUri,
        if (guideImagePrompt != null) 'guide_image_prompt': guideImagePrompt,
      };
}

class Recipe {
  final String recipeId;
  final String uid;
  final String title;
  final String? description;
  final String sourceType;
  final String? sourceUrl;
  final int? servings;
  final int? totalTimeMinutes;
  final String? difficulty;
  final String? cuisine;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;
  final List<String> techniqueTags;
  final List<String> ingredientsNormalized;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Recipe({
    required this.recipeId,
    this.uid = '',
    required this.title,
    this.description,
    this.sourceType = 'manual',
    this.sourceUrl,
    this.servings,
    this.totalTimeMinutes,
    this.difficulty,
    this.cuisine,
    this.ingredients = const [],
    this.steps = const [],
    this.techniqueTags = const [],
    this.ingredientsNormalized = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      recipeId: json['recipe_id'] as String? ?? '',
      uid: json['uid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      sourceType: json['source_type'] as String? ?? 'manual',
      sourceUrl: json['source_url'] as String?,
      servings: json['servings'] as int?,
      totalTimeMinutes: json['total_time_minutes'] as int?,
      difficulty: json['difficulty'] as String?,
      cuisine: json['cuisine'] as String?,
      ingredients: (json['ingredients'] as List<dynamic>?)
              ?.map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) => RecipeStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      techniqueTags:
          (json['technique_tags'] as List<dynamic>?)?.cast<String>() ?? [],
      ingredientsNormalized:
          (json['ingredients_normalized'] as List<dynamic>?)?.cast<String>() ??
              [],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  bool get isDemo => recipeId.startsWith('demo-');
}

/// Request model for creating/updating a recipe.
class RecipeCreateRequest {
  final String title;
  final String? description;
  final String sourceType;
  final String? sourceUrl;
  final int? servings;
  final int? totalTimeMinutes;
  final String? difficulty;
  final String? cuisine;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;

  const RecipeCreateRequest({
    required this.title,
    this.description,
    this.sourceType = 'manual',
    this.sourceUrl,
    this.servings,
    this.totalTimeMinutes,
    this.difficulty,
    this.cuisine,
    this.ingredients = const [],
    this.steps = const [],
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
        'source_type': sourceType,
        if (sourceUrl != null) 'source_url': sourceUrl,
        if (servings != null) 'servings': servings,
        if (totalTimeMinutes != null) 'total_time_minutes': totalTimeMinutes,
        if (difficulty != null) 'difficulty': difficulty,
        if (cuisine != null) 'cuisine': cuisine,
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  /// Validate the request; returns null if valid, error message otherwise.
  String? validate() {
    if (title.trim().isEmpty) return 'Title is required';
    if (ingredients.isEmpty) return 'At least one ingredient is required';
    if (steps.isEmpty) return 'At least one step is required';
    for (int i = 0; i < ingredients.length; i++) {
      if (ingredients[i].name.trim().isEmpty) {
        return 'Ingredient ${i + 1} needs a name';
      }
    }
    for (int i = 0; i < steps.length; i++) {
      if (steps[i].instruction.trim().isEmpty) {
        return 'Step ${i + 1} needs an instruction';
      }
    }
    return null;
  }
}

/// Per-ingredient check for the ingredient gate.
class IngredientCheck {
  final String ingredient;
  bool hasIt;

  IngredientCheck({required this.ingredient, this.hasIt = false});

  Map<String, dynamic> toJson() => {
        'ingredient': ingredient,
        'has_it': hasIt,
      };
}
