import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/watch_record.dart';
import '../utils/theme.dart';

class ContinueWatchingCard extends StatelessWidget {
  final WatchRecord record;
  final String imageUrl;
  final VoidCallback onTap;

  const ContinueWatchingCard({
    super.key,
    required this.record,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster with progress bar
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF2A2A2A),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: Icon(Icons.movie_outlined, color: Colors.grey, size: 32)),
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, color: Colors.grey, size: 32)),
                          )
                        : const Center(
                            child: Icon(Icons.movie_outlined, color: Colors.grey, size: 32)),
                  ),
                  // Progress bar at bottom
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                      child: LinearProgressIndicator(
                        value: record.progressPercent / 100.0,
                        minHeight: 4,
                        backgroundColor: Colors.grey[700],
                        valueColor: const AlwaysStoppedAnimation(FnTheme.danmuGreen),
                      ),
                    ),
                  ),
                  // Play icon overlay
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2, right: 2),
              child: Text(
                record.displayTitle,
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
