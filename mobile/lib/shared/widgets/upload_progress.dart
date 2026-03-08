import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media_pipeline.dart';

/// Shows upload progress indicator when upload takes >400ms.
class UploadProgressIndicator extends StatelessWidget {
  const UploadProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaPipeline>(
      builder: (context, pipeline, _) {
        if (!pipeline.isUploading) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: pipeline.uploadProgress > 0
                      ? pipeline.uploadProgress
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Text('${(pipeline.uploadProgress * 100).round()}%'),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: pipeline.cancelUpload,
                tooltip: 'Cancel upload',
              ),
            ],
          ),
        );
      },
    );
  }
}
