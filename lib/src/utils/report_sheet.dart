import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/errors/human_error.dart';
import 'package:serafim/src/data/services/report_service.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';
import 'package:serafim/src/utils/ui_text_field.dart';

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService(ref.watch(apiDioProvider)),
);

/// Asks why, then reports a post or a message to the SERAFIM admins. Says
/// so when it is done; the person reported is not told who reported them.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String id,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (_) => _ReportSheet(target: target, id: id),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.target, required this.id});

  final ReportTarget target;
  final String id;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(reportServiceProvider)
          .report(
            target: widget.target,
            id: widget.id,
            reason: reason,
            note: _note.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Thanks. The Serafim team will look at it.'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.target == ReportTarget.post ? 'post' : 'message';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'REPORT THIS ${what.toUpperCase()}',
              style: AppTextStyles.displayHeading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'The Serafim team sees a copy of it. Nobody is told who '
              'reported them.',
              style: AppTextStyles.smallDim,
            ),
            const SizedBox(height: 12),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      key: ValueKey('report-${r.name}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      value: r,
                      title: Text(r.label, style: AppTextStyles.fieldInput),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            UiTextField(
              label: 'ANYTHING TO ADD (OPTIONAL)',
              controller: _note,
              maxLength: 500,
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.rustPale),
              ),
            ],
            const SizedBox(height: 12),
            SerafimButton(
              key: const ValueKey('report-send'),
              label: _busy ? 'SENDING…' : 'REPORT',
              onPressed: _reason == null || _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
