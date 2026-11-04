import 'package:flutter/material.dart';

const String kTtsInstallBannerText = '음성 안내를 쓰려면 기기 설정에서 한국어 음성을 설치하세요.';

/// 한국어 오프라인 음성이 없을 때 홈 화면 상단에 표시하는 안내. 닫기는 세션 중에만 유지된다.
class TtsInstallBanner extends StatefulWidget {
  const TtsInstallBanner({super.key, required this.ttsAvailable});

  final bool ttsAvailable;

  @override
  State<TtsInstallBanner> createState() => _TtsInstallBannerState();
}

class _TtsInstallBannerState extends State<TtsInstallBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.ttsAvailable || _dismissed) return const SizedBox.shrink();
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            const Expanded(child: Text(kTtsInstallBannerText)),
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}
