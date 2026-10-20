import 'package:flutter/material.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// "Load more" under a list of posts, shown only while there are more.
class LoadMoreButton extends StatefulWidget {
  const LoadMoreButton({super.key, required this.onLoad});

  final Future<void> Function() onLoad;

  @override
  State<LoadMoreButton> createState() => _LoadMoreButtonState();
}

class _LoadMoreButtonState extends State<LoadMoreButton> {
  bool _busy = false;

  Future<void> _tap() async {
    setState(() => _busy = true);
    try {
      await widget.onLoad();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: _busy ? null : _tap,
      child: Text(
        _busy ? 'Loading…' : 'Load more',
        style: AppTextStyles.linkText,
      ),
    ),
  );
}
