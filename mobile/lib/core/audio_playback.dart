import 'dart:convert';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';

/// Plays back audio from base64-encoded PCM data with barge-in support.
///
/// Wraps PCM data in a WAV header for playback via just_audio.
/// Supports immediate stop (<200ms) for barge-in interruption.
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  bool get isPlaying => _playing;

  /// Play base64-encoded PCM audio.
  Future<void> play(String base64Audio, {String mimeType = 'audio/pcm'}) async {
    final bytes = base64Decode(base64Audio);
    _playing = true;
    await _player.setAudioSource(_PcmAudioSource(bytes));
    await _player.play();
    _playing = false;
  }

  /// Stop playback immediately for barge-in (<200ms target).
  Future<void> stopImmediately() async {
    _playing = false;
    await _player.stop();
  }

  /// Release all resources.
  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// Streams PCM data wrapped in a WAV header for just_audio playback.
class _PcmAudioSource extends StreamAudioSource {
  final Uint8List _pcmData;
  late final Uint8List _wavBytes;

  _PcmAudioSource(this._pcmData) {
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

  /// Build a standard 44-byte WAV header for raw PCM data.
  static Uint8List _buildWavHeader(
    int dataSize,
    int sampleRate,
    int channels,
    int bitsPerSample,
  ) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final buffer = ByteData(44);
    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    // WAVE
    buffer.setUint8(8, 0x57); // W
    buffer.setUint8(9, 0x41); // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E
    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little); // chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, channels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);
    return buffer.buffer.asUint8List();
  }
}
