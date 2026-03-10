import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_service.dart';
import '../models/scan_models.dart';
import '../services/scan_service.dart';

/// Scan flow phases.
enum ScanPhase { idle, uploading, detecting, reviewing, confirming, done }

/// State management for the full scan → detect → confirm → suggestions flow.
class ScanProvider extends ChangeNotifier {
  final ScanService _service;

  ScanProvider({required ApiClient apiClient, AuthService? authService})
      : _service = ScanService(api: apiClient, authService: authService);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  ScanPhase _phase = ScanPhase.idle;
  String? _scanId;
  String _source = 'fridge'; // "fridge" | "pantry"
  List<File> _selectedImages = [];
  List<DetectedIngredient> _detected = [];
  List<String> _confirmed = [];
  int _lowConfidenceCount = 0;
  SuggestionsResponse? _suggestions;
  ExplainResponse? _explain;
  bool _isLoading = false;
  String? _error;

  // Getters
  ScanPhase get phase => _phase;
  String? get scanId => _scanId;
  String get source => _source;
  List<File> get selectedImages => _selectedImages;
  List<DetectedIngredient> get detected => _detected;
  List<String> get confirmed => _confirmed;
  int get lowConfidenceCount => _lowConfidenceCount;
  SuggestionsResponse? get suggestions => _suggestions;
  ExplainResponse? get explain => _explain;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Set the source type (fridge or pantry).
  void setSource(String source) {
    _source = source;
    notifyListeners();
  }

  /// Add an image to the selection.
  void addImage(File file) {
    if (_selectedImages.length < 6) {
      _selectedImages.add(file);
      notifyListeners();
    }
  }

  /// Remove an image from the selection.
  void removeImage(int index) {
    if (index >= 0 && index < _selectedImages.length) {
      _selectedImages.removeAt(index);
      notifyListeners();
    }
  }

  /// Upload images and create scan, then auto-detect.
  Future<void> uploadAndDetect() async {
    if (_selectedImages.length < 2) {
      _error = 'Please select at least 2 images';
      notifyListeners();
      return;
    }

    _error = null;
    _isLoading = true;
    _phase = ScanPhase.uploading;
    notifyListeners();

    try {
      // Step 1: Upload
      final scanResult = await _service.createScan(
        source: _source,
        imageFiles: _selectedImages,
      );
      _scanId = scanResult.scanId;

      // Step 2: Detect
      _phase = ScanPhase.detecting;
      notifyListeners();

      final detectResult = await _service.detectIngredients(_scanId!);
      _detected = detectResult.detectedIngredients;
      _lowConfidenceCount = detectResult.lowConfidenceCount;

      // Pre-populate confirmed list with detected names
      _confirmed = _detected.map((d) => d.nameNormalized).toList();

      _phase = ScanPhase.reviewing;
    } on ApiException catch (e) {
      _error = e.message;
      _phase = ScanPhase.idle;
    } catch (e) {
      _error = 'Failed to scan ingredients. Please try again.';
      _phase = ScanPhase.idle;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Upload a video and detect ingredients from it.
  Future<void> uploadVideoAndDetect(File videoFile) async {
    _error = null;
    _isLoading = true;
    _phase = ScanPhase.uploading;
    notifyListeners();

    try {
      // Step 1: Upload video
      final scanResult = await _service.createVideoScan(
        source: _source,
        videoFile: videoFile,
      );
      _scanId = scanResult.scanId;

      // Step 2: Detect
      _phase = ScanPhase.detecting;
      notifyListeners();

      final detectResult = await _service.detectIngredients(_scanId!);
      _detected = detectResult.detectedIngredients;
      _lowConfidenceCount = detectResult.lowConfidenceCount;

      // Pre-populate confirmed list with detected names
      _confirmed = _detected.map((d) => d.nameNormalized).toList();

      _phase = ScanPhase.reviewing;
    } on ApiException catch (e) {
      _error = e.message;
      _phase = ScanPhase.idle;
    } catch (e) {
      _error = 'Failed to scan video. Please try again.';
      _phase = ScanPhase.idle;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggle an ingredient in the confirmed list.
  void toggleIngredient(String name) {
    if (_confirmed.contains(name)) {
      _confirmed.remove(name);
    } else {
      _confirmed.add(name);
    }
    notifyListeners();
  }

  /// Add a manually-entered ingredient.
  void addManualIngredient(String name) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isNotEmpty && !_confirmed.contains(trimmed)) {
      _confirmed.add(trimmed);
      notifyListeners();
    }
  }

  /// Remove an ingredient from the confirmed list.
  void removeIngredient(String name) {
    _confirmed.remove(name);
    notifyListeners();
  }

  /// Confirm ingredients and fetch suggestions.
  Future<void> confirmAndGetSuggestions() async {
    if (_scanId == null || _confirmed.isEmpty) return;

    _error = null;
    _isLoading = true;
    _phase = ScanPhase.confirming;
    notifyListeners();

    try {
      await _service.confirmIngredients(_scanId!, _confirmed);
      final suggestions = await _service.getSuggestions(_scanId!);
      _suggestions = suggestions;
      _phase = ScanPhase.done;
    } on ApiException catch (e) {
      _error = e.message;
      _phase = ScanPhase.reviewing;
    } catch (e) {
      _error = 'Failed to get suggestions. Please try again.';
      _phase = ScanPhase.reviewing;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch an expanded explanation for a suggestion.
  Future<void> loadExplanation(String suggestionId) async {
    if (_scanId == null) return;
    _explain = null;
    notifyListeners();

    try {
      _explain = await _service.explainSuggestion(_scanId!, suggestionId);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Failed to load explanation.';
    }
    notifyListeners();
  }

  /// Start a cooking session from a suggestion.
  Future<StartSessionResponse?> startSession(String suggestionId) async {
    if (_scanId == null) return null;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.startSession(_scanId!, suggestionId);
      return result;
    } on ApiException catch (e) {
      _error = e.message;
      return null;
    } catch (e) {
      _error = 'Failed to start session.';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset to start a new scan.
  void reset() {
    _phase = ScanPhase.idle;
    _scanId = null;
    _source = 'fridge';
    _selectedImages = [];
    _detected = [];
    _confirmed = [];
    _lowConfidenceCount = 0;
    _suggestions = null;
    _explain = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Clear error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Set suggestions directly (for testing).
  @visibleForTesting
  void setSuggestionsForTest(SuggestionsResponse suggestions) {
    _suggestions = suggestions;
    _phase = ScanPhase.done;
    notifyListeners();
  }
}
