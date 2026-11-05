import 'package:flutter/material.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';
import 'package:mukmuk_app/packs/pack_update_controller.dart';

const String kFirstRunNotWifiMessage = 'Wi-Fi에서 팩을 받아야 사용할 수 있습니다';

/// 팩이 없을 때 첫 실행에서 팩을 내려받는 화면. 성공하면 [onReady]를 부른다.
class FirstRunDownloadScreen extends StatefulWidget {
  const FirstRunDownloadScreen({
    super.key,
    required this.controller,
    required this.onReady,
  });

  final PackUpdateController controller;
  final VoidCallback onReady;

  @override
  State<FirstRunDownloadScreen> createState() => _FirstRunDownloadScreenState();
}

class _FirstRunDownloadScreenState extends State<FirstRunDownloadScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.check();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final s = widget.controller.value;
    if (s.status == PackUpdateStatus.updated) widget.onReady();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<PackUiState>(
            valueListenable: widget.controller,
            builder: (context, s, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.message ?? '데이터 팩을 준비하는 중', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (s.busy)
                  LinearProgressIndicator(
                    value: s.phase == PackUiPhase.downloading
                        ? s.progress
                        : null,
                  )
                else if (s.status != PackUpdateStatus.updated)
                  FilledButton(
                    onPressed: widget.controller.check,
                    child: const Text('다시 시도'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
