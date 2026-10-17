import 'dart:convert';
import 'dart:typed_data';

/// What the server found at a link (backend `LinkPreviewResponse`).
class LinkPreview {
  const LinkPreview({
    required this.url,
    required this.domain,
    this.title,
    this.description,
    this.siteName,
    this.image,
  });

  final String url;
  final String domain;
  final String? title;
  final String? description;
  final String? siteName;

  /// Thumbnail as a `data:` URI, fetched by the server.
  final String? image;

  /// The thumbnail's bytes, or null when there is none (or it is malformed).
  Uint8List? get imageBytes {
    final uri = image;
    if (uri == null || !uri.startsWith('data:image/')) return null;
    final comma = uri.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(uri.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'domain': domain,
    'title': title,
    'description': description,
    'site_name': siteName,
    'image': image,
  };

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    url: json['url'] as String,
    domain: json['domain'] as String? ?? '',
    title: json['title'] as String?,
    description: json['description'] as String?,
    siteName: json['site_name'] as String?,
    image: json['image'] as String?,
  );
}
