import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/play_list_item.dart';
import '../utils/theme.dart';

class MediaCard extends StatelessWidget {
  static const double cardWidth = 112;
  static const double posterAspect = 2 / 3;

  final PlayListItem item;
  final String imageUrl;
  final VoidCallback onTap;
  final bool showTitle;

  const MediaCard({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.onTap,
    this.showTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final headers = context.read<AppState>().api.imageHeaders;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: posterAspect,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF2A2A2A),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        httpHeaders: headers,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) => Container(color: const Color(0xFF2A2A2A)),
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey, size: 28),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.movie_outlined, color: Colors.grey, size: 28),
                      ),
              ),
            ),
            if (showTitle) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.categoryLabel, style: const TextStyle(
                  fontSize: 10, color: FnTheme.textMuted)),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                item.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: FnTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
