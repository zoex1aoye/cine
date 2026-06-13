import 'package:flutter/material.dart';
import '../models/mubu_models.dart';
import '../api/mubu_api_client.dart';
import 'movie_card.dart';

class MovieSliverGrid extends StatelessWidget {
  final List<VideoItem> videos;
  final Function(VideoItem) onPlay;
  final Function(VideoItem) onInfo;
  final Function(VideoItem)? onDelete;
  final String? imgDomain;
  final bool? showSubtitle;

  const MovieSliverGrid({
    super.key,
    required this.videos,
    required this.onPlay,
    required this.onInfo,
    this.onDelete,
    this.imgDomain,
    this.showSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedImgDomain = imgDomain ?? MubuApiClient.instance.imgDomain;
    final resolvedShowSubtitle = showSubtitle ?? (onDelete == null);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.crossAxisExtent;
        final spacing = 14.0;

        // 响应式布局：根据屏幕宽度调整卡片尺寸和列数
        final cols = calculateColumns(w);

        // 重新计算实际卡片宽度，确保填满可用空间
        final actualCardWidth = (w - (cols - 1) * spacing) / cols;

        // 将视频列表分组为行
        final rows = <List<VideoItem>>[];
        for (var i = 0; i < videos.length; i += cols) {
          rows.add(videos.sublist(i, (i + cols).clamp(0, videos.length)));
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final row = rows[index];
              return Padding(
                padding: EdgeInsets.only(bottom: index < rows.length - 1 ? spacing : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int colIndex = 0; colIndex < row.length; colIndex++) ...[
                      if (colIndex > 0) SizedBox(width: spacing),
                      SizedBox(
                        width: actualCardWidth,
                        child: MovieCard(
                          key: ValueKey(row[colIndex].id),
                          video: row[colIndex],
                          imgDomain: resolvedImgDomain,
                          onPlay: () => onPlay(row[colIndex]),
                          onInfo: () => onInfo(row[colIndex]),
                          onDelete: onDelete != null ? () => onDelete!(row[colIndex]) : null,
                          showSubtitle: resolvedShowSubtitle,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
            childCount: rows.length,
          ),
        );
      },
    );
  }

  /// 根据屏幕宽度返回计算后的列数
  static int calculateColumns(double width) {
    final spacing = 14.0;
    final cardWidth = getCardWidth(width);
    final maxCols = getMaxColumns(width);
    int cols = ((width + spacing) / (cardWidth + spacing)).ceil();
    return cols.clamp(2, maxCols);
  }

  /// 根据屏幕宽度返回推荐的卡片宽度
  static double getCardWidth(double screenWidth) {
    if (screenWidth < 500) {
      // 手机竖屏：120-140px
      return 130.0;
    } else if (screenWidth < 900) {
      // 手机横屏 / 小平板：140-160px
      return 150.0;
    } else if (screenWidth < 1200) {
      // iPad / 平板：160-180px
      return 170.0;
    } else if (screenWidth < 1600) {
      // 笔记本：180-200px
      return 190.0;
    } else {
      // 电视 / 大屏：200-220px
      return 210.0;
    }
  }

  /// 根据屏幕宽度返回最大列数限制
  static int getMaxColumns(double screenWidth) {
    if (screenWidth < 500) {
      // 手机竖屏：最多3列
      return 3;
    } else if (screenWidth < 900) {
      // 手机横屏 / 小平板：最多5列
      return 5;
    } else if (screenWidth < 1200) {
      // iPad / 平板：最多6列
      return 6;
    } else if (screenWidth < 1600) {
      // 笔记本：最多8列
      return 8;
    } else {
      // 电视 / 大屏：最多10列
      return 10;
    }
  }
}
