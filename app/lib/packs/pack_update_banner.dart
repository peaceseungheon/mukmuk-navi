import 'package:flutter/material.dart';
import 'package:mukmuk_app/packs/pack_update_controller.dart';

/// 데이터 팩 업데이트 진행률·결과 배너. 메시지가 없으면 아무것도 그리지 않는다.
class PackUpdateBanner extends StatelessWidget {
  const PackUpdateBanner({super.key, required this.controller});

  final PackUpdateController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PackUiState>(
      valueListenable: controller,
      builder: (context, s, _) {
        final text = s.message;
        if (text == null) return const SizedBox.shrink();
        return Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(text)),
                    if (!s.busy) ...[
                      TextButton(
                        onPressed: controller.check,
                        child: const Text('다시 확인'),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close),
                        onPressed: controller.dismiss,
                      ),
                    ],
                  ],
                ),
                if (s.busy)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: LinearProgressIndicator(
                      value: s.phase == PackUiPhase.downloading
                          ? s.progress
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
