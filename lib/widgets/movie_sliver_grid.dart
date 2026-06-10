import 'package:flutter/material.dart';
import '../models/mubu_models.dart';
import '../api/mubu_ui_adapt.dart';
import '../api/mubu_api_client.dart';
import 'movie_card.dart';

class MovieSliverGrid extends StatelessWidget {
  final List<VideoItem> videos;
  final Function(VideoItem) onPlay;
  final Function(VideoItem) onInfo;
  final Function(VideoItem)? onDelete;
  final String? imgDomain;

  const MovieSliverGrid({
    super.key,
    required this.videos,
    required this.onPlay,
    required this.onInfo,
    this.onDelete,
    this.imgDomain,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedImgDomain = imgDomain ?? MubuApiClient.instance.imgDomain;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.crossAxisExtent;
        final maxExtent = 180.0 * UIAdapt.scale(context);
        const spacing = 14.0;
        int cols = ((w + spacing) / (maxExtent + spacing)).ceil();
        if (cols < 2) cols = 2;

        final cardWidth = (w - (cols - 1) * spacing) / cols;
        final cardHeight = cardWidth * 11 / 16 + 56.0;
        final ratio = cardWidth / cardHeight;

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: ratio,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 20,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final video = videos[index];
              return MovieCard(
                key: ValueKey(video.id),
                video: video,
                imgDomain: resolvedImgDomain,
                onPlay: () => onPlay(video),
                onInfo: () => onInfo(video),
                onDelete: onDelete != null ? () => onDelete!(video) : null,
              );
            },
            childCount: videos.length,
          ),
        );
      },
    );
  }
}
