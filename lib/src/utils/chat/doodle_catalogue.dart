import 'package:serafim/src/utils/chat/doodle_bounds.g.dart';
import 'package:serafim/src/utils/chat/doodle_kit.dart';
import 'package:serafim/src/utils/chat/doodles_creatures.dart';
import 'package:serafim/src/utils/chat/doodles_things.dart';

export 'package:serafim/src/utils/chat/doodle_kit.dart'
    show Doodle, DoodleBounds, DoodleInk;

/// Everything on the wallpaper. Big doodles anchor the pattern; fillers are the
/// small marks that fill the gaps between them.
const List<Doodle> bigDoodles = [
  // Faces and characters
  Doodle('goofy face', goofyFace),
  Doodle('dizzy face', dizzyFace),
  Doodle('scream face', screamFace),
  Doodle('silly cat', sillyCat),
  Doodle('ghost', goofyGhost),
  Doodle('goofy angel', goofyAngel),
  Doodle('sleepy face', sleepyFace),
  Doodle('disguise', disguise),
  Doodle('frog', frog),
  Doodle('snail', snail),
  // Objects with faces
  Doodle('cloud', cloudFace),
  Doodle('cool sun', coolSun),
  Doodle('sleepy moon', sleepyMoon),
  Doodle('cactus', cactusFace),
  Doodle('cupcake', cupcake),
  Doodle('coffee mug', coffeeMug),
  Doodle('burger', burger),
  Doodle('taco', taco),
  Doodle('lightbulb', lightbulb),
  Doodle('heart face', heartFace),
  Doodle('star face', starFace),
  Doodle('mushroom', mushroom),
  Doodle('cheese', cheese),
  Doodle('apple worm', appleWorm),
  Doodle('balloon', balloon),
  Doodle('planet', planet),
  Doodle('toast', toast),
  Doodle('watermelon', watermelon),
  Doodle('alarm clock', alarmClock),
  Doodle('avocado', avocado),
  Doodle('melting cone', meltingScoop),
  // Food and mess
  Doodle('ice cream spill', iceCreamSpill),
  Doodle('donut', donut),
  Doodle('pizza', pizza),
  Doodle('banana', banana),
  Doodle('spilled drink', spilledDrink),
  Doodle('rubber duck', rubberDuck),
  Doodle('ice pop', icePop),
  Doodle('cherries', cherries),
  // Just things
  Doodle('rocket', rocket),
  Doodle('umbrella', umbrella),
  Doodle('key', keyDoodle),
  Doodle('lollipop', lollipop),
  Doodle('paper plane', paperPlane),
  Doodle('potted plant', pottedPlant),
  Doodle('headphones', headphones),
  Doodle('camera', camera),
  Doodle('sneaker', sneaker),
  Doodle('daisy', daisy),
  Doodle('fish', fish),
  Doodle('crown', crown),
  Doodle('love letter', loveLetter),
  Doodle('typing bubble', typingBubble),
  Doodle('shock bubble', shockBubble),
  Doodle('pencil', pencil),
];

const List<Doodle> fillerDoodles = [
  Doodle('sparkle', sparkleFiller, filler: true),
  Doodle('heart', heartFiller, filler: true),
  Doodle('star', starFiller, filler: true),
  Doodle('squiggle', squiggleFiller, filler: true),
  Doodle('zigzag', zigzagFiller, filler: true),
  Doodle('bolt', boltFiller, filler: true),
  Doodle('dots', dotsFiller, filler: true),
  Doodle('ring', ringFiller, filler: true),
  Doodle('plus', plusFiller, filler: true),
  Doodle('swirl', swirlFiller, filler: true),
  Doodle('note', musicNote, filler: true),
  Doodle('cross', crossX, filler: true),
  Doodle('crescent', tinyCrescent, filler: true),
  Doodle('flower', tinyFlower, filler: true),
  Doodle('leaf', leaf, filler: true),
  Doodle('triangle', triangleOutline, filler: true),
  Doodle('asterisk', asterisk, filler: true),
  Doodle('tiny cloud', tinyCloud, filler: true),
];

List<Doodle> get allDoodles => [...bigDoodles, ...fillerDoodles];

/// The measured bounds of [d] (see `doodle_bounds.g.dart`).
DoodleBounds boundsOf(Doodle d) =>
    doodleBounds[d.name] ?? const DoodleBounds(0, 0, 34);
