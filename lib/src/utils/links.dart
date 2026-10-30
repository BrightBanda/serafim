import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:serafim/src/utils/emoji.dart';
import 'package:url_launcher/url_launcher.dart';

/// A web link found in a message.
class LinkMatch {
  const LinkMatch(this.start, this.end, this.text, this.uri);

  final int start;
  final int end;

  /// Exactly as typed.
  final String text;

  /// What opening it visits (always http or https).
  final Uri uri;
}

// http(s)://… or www.…, up to whitespace. Trailing punctuation that usually
// ends a sentence is trimmed afterwards.
final _linkPattern = RegExp(
  r'''(?:(?:https?://)|(?:www\.))[^\s<>"']+''',
  caseSensitive: false,
);
const _trailing = '.,;:!?)]}\'"…';

/// A safe http(s) URI for [raw], or null. `www.` links get https://.
Uri? safeHttpUri(String raw) {
  var text = raw.trim();
  if (text.toLowerCase().startsWith('www.')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || !uri.host.contains('.')) return null;
  return uri;
}

/// Every http(s) link in [text], in order.
List<LinkMatch> findLinks(String text) {
  final found = <LinkMatch>[];
  for (final m in _linkPattern.allMatches(text)) {
    var end = m.end;
    while (end > m.start && _trailing.contains(text[end - 1])) {
      // Keep a closing bracket that has its opening one inside the link,
      // e.g. https://en.wikipedia.org/wiki/Dart_(language)
      final c = text[end - 1];
      final open = switch (c) {
        ')' => '(',
        ']' => '[',
        '}' => '{',
        _ => null,
      };
      final inner = text.substring(m.start, end - 1);
      if (open != null &&
          open.allMatches(inner).length > c.allMatches(inner).length) {
        break;
      }
      end--;
    }
    final raw = text.substring(m.start, end);
    final uri = safeHttpUri(raw);
    if (uri != null) found.add(LinkMatch(m.start, end, raw, uri));
  }
  return found;
}

/// The first link in [text], for its preview card.
Uri? firstLink(String text) {
  final links = findLinks(text);
  return links.isEmpty ? null : links.first.uri;
}

/// Opens [uri] in the browser. Returns false if nothing could open it.
Future<bool> openLink(Uri uri) async {
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Text with its links underlined and tappable (opening in the browser).
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    required this.style,
    required this.linkColor,
    this.emojiScale = 1.0,
    this.maxLines,
    this.overflow,
  });

  /// Emoji are drawn this many times larger than the text around them.
  final double emojiScale;

  final String text;
  final TextStyle style;
  final Color linkColor;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri uri) async {
    final ok = await openLink(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't open that link.")),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = findLinks(widget.text);
    final base = widget.style.fontSize ?? 14;
    // Plain stretches of text, with their emoji enlarged.
    List<InlineSpan> plain(String s) => widget.emojiScale == 1.0
        ? [TextSpan(text: s)]
        : emojiSizedSpans(s, base, widget.emojiScale);
    if (links.isEmpty) {
      return widget.emojiScale == 1.0
          ? Text(
              widget.text,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            )
          : Text.rich(
              TextSpan(style: widget.style, children: plain(widget.text)),
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            );
    }

    _disposeRecognizers();
    final spans = <InlineSpan>[];
    var at = 0;
    for (final link in links) {
      if (link.start > at) {
        spans.addAll(plain(widget.text.substring(at, link.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(link.uri);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: link.text,
          recognizer: recognizer,
          style: TextStyle(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
          ),
        ),
      );
      at = link.end;
    }
    if (at < widget.text.length) {
      spans.addAll(plain(widget.text.substring(at)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
