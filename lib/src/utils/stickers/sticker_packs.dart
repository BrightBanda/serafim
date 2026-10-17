import 'package:serafim/src/utils/chat/doodle_catalogue.dart';
import 'package:serafim/src/utils/chat/doodle_kit.dart';

/// How a sticker moves (where animation is on).
enum StickerMotion { none, bounce, wobble, pulse, float }

/// One sticker. Its [id] (`pack/name`) is what a message carries; the art is
/// drawn by the app, so stickers cost nothing to send and work offline.
class Sticker {
  const Sticker({
    required this.id,
    required this.name,
    required this.draw,
    required this.bounds,
    this.motion = StickerMotion.none,
  });

  final String id;
  final String name;
  final DoodleDraw draw;
  final DoodleBounds bounds;
  final StickerMotion motion;
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.stickers,
  });

  final String id;
  final String name;
  final List<Sticker> stickers;
}

/// Turns a display name into an id part: lowercase letters, digits and _.
String stickerSlug(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

/// The starter pack: the wallpaper's doodle characters as stickers.
StickerPack _doodlePack() {
  const motions = {
    'goofy face': StickerMotion.wobble,
    'ghost': StickerMotion.float,
    'frog': StickerMotion.bounce,
    'heart face': StickerMotion.pulse,
    'cool sun': StickerMotion.wobble,
    'rocket': StickerMotion.float,
    'rubber duck': StickerMotion.bounce,
    'balloon': StickerMotion.float,
    'star face': StickerMotion.pulse,
    'dizzy face': StickerMotion.wobble,
  };
  const picks = [
    'goofy face',
    'dizzy face',
    'scream face',
    'silly cat',
    'ghost',
    'goofy angel',
    'sleepy face',
    'disguise',
    'frog',
    'snail',
    'cloud',
    'cool sun',
    'sleepy moon',
    'cactus',
    'cupcake',
    'coffee mug',
    'burger',
    'taco',
    'heart face',
    'star face',
    'pizza',
    'donut',
    'rubber duck',
    'rocket',
    'balloon',
    'love letter',
    'crown',
    'shock bubble',
  ];
  final byName = {for (final d in bigDoodles) d.name: d};
  return StickerPack(
    id: 'doodles',
    name: 'Doodle Gang',
    stickers: [
      for (final name in picks)
        if (byName[name] case final d?)
          Sticker(
            id: 'doodles/${stickerSlug(name)}',
            name: name,
            draw: d.draw,
            bounds: boundsOf(d),
            motion: motions[name] ?? StickerMotion.none,
          ),
    ],
  );
}

/// Every pack the app ships, in picker order. Add new packs here; ids must
/// stay stable once released, because messages refer to them.
final List<StickerPack> stickerPacks = [_doodlePack()];

final Map<String, Sticker> _byId = {
  for (final pack in stickerPacks)
    for (final s in pack.stickers) s.id: s,
};

/// The sticker with [id], or null if this version of the app doesn't have it
/// (e.g. sent from a newer version with more packs).
Sticker? stickerById(String id) => _byId[id];
