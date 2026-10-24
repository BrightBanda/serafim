import 'dart:ui' show Brightness;

/// Quality used when shrinking photos before they are sent or uploaded.
enum ImageQuality {
  dataSaver('Data saver', 'Smaller files, lower detail', 800, 60),
  standard('Standard', 'Balanced size and detail', 1280, 75),
  high('High', 'Larger files, more detail', 1920, 85);

  const ImageQuality(
    this.label,
    this.description,
    this.maxSide,
    this.jpegQuality,
  );

  final String label;
  final String description;

  /// Longest edge in pixels.
  final int maxSide;
  final int jpegQuality;

  static ImageQuality parse(String? name) => ImageQuality.values.firstWhere(
    (q) => q.name == name,
    orElse: () => ImageQuality.standard,
  );
}

/// Light, dark, or follow the phone.
enum ThemeChoice {
  system('Match system', 'Follows your phone\'s light/dark setting'),
  light('Light', 'Bright surfaces'),
  dark('Dark', 'The original Serafim look');

  const ThemeChoice(this.label, this.description);

  final String label;
  final String description;

  static ThemeChoice parse(String? name) => ThemeChoice.values.firstWhere(
    (t) => t.name == name,
    orElse: () => ThemeChoice.system,
  );

  /// The brightness to draw with, given what the phone is currently set to.
  Brightness resolve(Brightness platform) => switch (this) {
    ThemeChoice.light => Brightness.light,
    ThemeChoice.dark => Brightness.dark,
    ThemeChoice.system => platform,
  };
}

/// How large text is across the app.
enum TextSize {
  small('Small', 0.9),
  normal('Default', 1.0),
  large('Large', 1.15),
  extraLarge('Extra large', 1.3);

  const TextSize(this.label, this.scale);

  final String label;
  final double scale;

  static TextSize parse(String? name) => TextSize.values.firstWhere(
    (t) => t.name == name,
    orElse: () => TextSize.normal,
  );
}

/// Choices for how long messages are kept on this device. 0 = forever.
const retentionChoices = <int, String>{
  0: 'Keep forever',
  30: '30 days',
  90: '90 days',
  365: '1 year',
};

/// Device-level preferences. (Anything that other people's apps must respect —
/// like who may send you friend requests — lives on the server profile
/// instead.)
class AppSettings {
  const AppSettings({
    this.sendReadReceipts = true,
    this.inAppAlerts = true,
    this.alertSound = true,
    this.wingsBreakThrough = true,
    this.imageQuality = ImageQuality.standard,
    this.retentionDays = 0,
    this.textSize = TextSize.normal,
    this.themeChoice = ThemeChoice.system,
    this.pushNotifications = true,
    this.pushPreviews = true,
  });

  /// When off, opening a chat no longer tells the sender you read it.
  final bool sendReadReceipts;

  /// Banner for messages that arrive while you are in another screen.
  final bool inAppAlerts;
  final bool alertSound;

  /// Messages from your Wings still get a banner when banners are off.
  final bool wingsBreakThrough;

  final ImageQuality imageQuality;

  /// Messages older than this many days are removed from this device.
  final int retentionDays;

  final TextSize textSize;

  /// Light, dark, or follow the phone.
  final ThemeChoice themeChoice;

  /// Push notifications for messages that arrive while the app is closed.
  final bool pushNotifications;

  /// Whether a push shows the message text (otherwise just "New message").
  final bool pushPreviews;

  AppSettings copyWith({
    bool? sendReadReceipts,
    bool? inAppAlerts,
    bool? alertSound,
    bool? wingsBreakThrough,
    ImageQuality? imageQuality,
    int? retentionDays,
    TextSize? textSize,
    ThemeChoice? themeChoice,
    bool? pushNotifications,
    bool? pushPreviews,
  }) {
    return AppSettings(
      sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
      inAppAlerts: inAppAlerts ?? this.inAppAlerts,
      alertSound: alertSound ?? this.alertSound,
      wingsBreakThrough: wingsBreakThrough ?? this.wingsBreakThrough,
      imageQuality: imageQuality ?? this.imageQuality,
      retentionDays: retentionDays ?? this.retentionDays,
      textSize: textSize ?? this.textSize,
      themeChoice: themeChoice ?? this.themeChoice,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      pushPreviews: pushPreviews ?? this.pushPreviews,
    );
  }
}
