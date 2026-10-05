import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/mubu_models.dart';
import '../api/mubu_api_client.dart';
import '../utils/cine_surface.dart';
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
      // 手机竖屏
      return 110.0;
    } else if (screenWidth < 900) {
      // 手机横屏 / 小平板
      return 140.0;
    } else if (screenWidth < 1200) {
      // iPad / 平板
      return 170.0;
    } else if (screenWidth < 1600) {
      // 笔记本
      return 220.0;
    } else {
      // 电视 / 大屏
      return 260.0;
    }
  }

  /// 根据屏幕宽度返回最大列数限制。
  /// 电视保持 3/4/5/6/8；非电视显示屏放宽为 3/5/6/8/12。
  static int getMaxColumns(double screenWidth) {
    if (screenWidth < 500) return 3;
    if (isTvSurface) {
      if (screenWidth < 900) return 4;
      if (screenWidth < 1200) return 5;
      if (screenWidth < 1600) return 6;
      return 8;
    }
    if (screenWidth < 900) return 5;
    if (screenWidth < 1200) return 6;
    if (screenWidth < 1600) return 8;
    return 12;
  }

  static const int homeTagFetchMin = 6;
  static const int homeTagFetchMax = 30;

  /// 电视首页一行固定请求条数，够其最多 8 列。
  static const int tvHomeTagFetchCount = 12;

  /// 非电视首页一行请求条数：至少 [homeTagFetchMin]，封顶 [homeTagFetchMax]。
  static int homeTagFetchCountForColumns(int columns) {
    return math.min(homeTagFetchMax, math.max(columns, homeTagFetchMin));
  }

  /// 首页 tag 一行应请求的条数。电视固定 12，非电视跟着列数走。
  static int homeTagRowFetchCount(double contentWidth) {
    if (isTvSurface) return tvHomeTagFetchCount;
    return homeTagFetchCountForColumns(calculateColumns(contentWidth));
  }

  /// 变宽且没有请求在飞时才补拉。变窄（needed 更小）不请求。
  static bool homeTagRowNeedsRefetch({
    required int lastRequestedCount,
    required int needed,
    required bool fetching,
  }) {
    return !fetching && lastRequestedCount < needed;
  }
}
