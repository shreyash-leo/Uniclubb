import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatDate(dynamic value, {bool time = true}) {
  final parsed =
      value is DateTime ? value : DateTime.tryParse('$value') ?? DateTime.now();
  return DateFormat(time ? 'EEE, d MMM · h:mm a' : 'd MMM yyyy')
      .format(parsed.toLocal());
}

Future<void> disposeTextControllersAfterRoute(
  Iterable<TextEditingController> controllers,
) async {
  await WidgetsBinding.instance.endOfFrame;
  for (final controller in controllers) {
    controller.dispose();
  }
}

void showErrorSnackBar(BuildContext context, Object error) {
  final message =
      error.toString().replaceFirst('PostgrestException(message: ', '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
        content: Text(message.length > 180
            ? 'The action failed. Please try again.'
            : message)),
  );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: 82,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
}

class NetworkPicture extends StatelessWidget {
  const NetworkPicture({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 16,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final value = url;
    if (value == null || value.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: const Icon(Icons.image_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: value,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class AsyncErrorState extends StatelessWidget {
  const AsyncErrorState({
    super.key,
    this.error,
    this.onRetry,
    this.title = 'Could not load this page',
  });

  final Object? error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.value, {super.key});
  final String value;

  @override
  Widget build(BuildContext context) {
    final normalized = value.toLowerCase();
    final color = switch (normalized) {
      'approved' || 'active' || 'paid' || 'completed' => Colors.green,
      'rejected' || 'suspended' || 'cancelled' || 'failed' => Colors.red,
      'waitlisted' => Colors.purple,
      _ => Colors.orange,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: .12),
      side: BorderSide.none,
      label: Text(value.replaceAll('_', ' '),
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
