import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/play_list_item.dart';
import '../utils/theme.dart';

class MediaCard extends StatelessWidget {
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF2A2A2A),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        httpHeaders: context.read<AppState>().api.imageHeaders,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: Icon(Icons.movie_outlined, color: Colors.grey, size: 32)),
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey, size: 32)),
                      )
                    : const Center(
                        child: Icon(Icons.movie_outlined, color: Colors.grey, size: 32)),
              ),
            ),
            // Type tag
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Text(item.categoryLabel, style: const TextStyle(
                fontSize: 10, color: FnTheme.textMuted)),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 2, bottom: 2),
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
