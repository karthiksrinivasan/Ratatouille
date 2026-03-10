import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Captures microphone audio as base64-encoded PCM16 chunks.
///
/// Used for continuous voice input during live cooking sessions.
/// Audio is streamed at 16kHz mono for optimal speech recognition.
class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  bool _recording = false;

  bool get isRecording => _recording;

  /// Start capturing audio from the microphone.
  ///
  /// [onAudioChunk] is called with base64-encoded PCM16 data for each chunk.
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

  /// Stop capturing audio.
  Future<void> stop() async {
    _recording = false;
    await _streamSub?.cancel();
    _streamSub = null;
    await _recorder.stop();
  }

  /// Release all resources.
  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }
}
