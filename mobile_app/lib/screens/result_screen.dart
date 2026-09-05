import 'package:flutter/material.dart';
import '../models/diagnosis.dart';
import '../widgets/leaf_severity_indicator.dart';
import '../widgets/gradient_app_bar.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final diagnosis = ModalRoute.of(context)!.settings.arguments as Diagnosis;

    if (!diagnosis.isValidLeaf) {
      return Scaffold(
        appBar: const GradientAppBar(title: 'Verification Failed'),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                diagnosis.rejectionReason ?? 'Image could not be verified.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Retake Photo'),
              ),
            ],
          ),
        ),
      );
    }

    if (diagnosis.isUnknownCrop) {
      return Scaffold(
        appBar: const GradientAppBar(title: 'Crop Not Recognized'),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.help_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'This crop or disease could not be confidently identified. '
                'It may not be one of the crops this model was trained on.',
                textAlign: TextAlign.center,
              ),
              if (diagnosis.confidence != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Confidence: ${(diagnosis.confidence! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Try Another Photo'),
              ),
            ],
          ),
        ),
      );
    }

    final stage = diagnosis.severityStage!;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Diagnosis Result'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(diagnosis.imageUrl, height: 220, fit: BoxFit.cover),
            ),
            const SizedBox(height: 20),
            Text(diagnosis.predictedDisease ?? 'Unknown',
                style: Theme.of(context).textTheme.titleLarge),
            if (diagnosis.confidence != null)
              Text('Confidence: ${(diagnosis.confidence! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            Center(
              child: LeafSeverityIndicator(
                severityPercent: diagnosis.severityPercent ?? 0,
                stageCode: stage.code,
                stageLabel: stage.label,
                size: 120,
              ),
            ),
            const SizedBox(height: 24),
            Text('Recommended Treatment',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(diagnosis.treatmentRecommendation ?? 'No recommendation available.'),
            const SizedBox(height: 20),
            Text('Prevention Guidance',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(diagnosis.preventionTips ?? 'No prevention guidance available.'),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.smart_toy),
              label: const Text('Ask AI Assistant about this'),
              onPressed: () => Navigator.pushNamed(context, '/assistant'),
            ),
          ],
        ),
      ),
    );
  }
}
