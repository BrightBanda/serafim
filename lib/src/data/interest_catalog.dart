import 'package:flutter/material.dart';

/// Interests offered when setting up or editing a profile, grouped for
/// display. People can also add their own (see [InterestPicker]); matching
/// between profiles ignores case and spacing, so custom entries still match.
const interestCatalog = <String, List<String>>{
  'Sports': [
    'Soccer',
    'Basketball',
    'Running',
    'Cycling',
    'Swimming',
    'Tennis',
    'Volleyball',
    'Netball',
    'Boxing',
    'Gym & fitness',
    'Yoga',
    'Martial arts',
  ],
  'Hobbies': [
    'Gaming',
    'Cooking',
    'Photography',
    'Reading',
    'Stargazing',
    'Gardening',
    'Writing',
    'Drawing',
    'Painting',
    'Knitting',
    'Collecting',
    'Board games',
  ],
  'Entertainment': [
    'Movies',
    'Music',
    'Anime',
    'Podcasts',
    'Comics',
    'TV series',
    'Stand-up comedy',
    'K-drama',
    'Theatre',
    'Concerts',
  ],
  'Music': [
    'Hip-hop',
    'Afrobeats',
    'Gospel',
    'Rock',
    'Jazz',
    'Classical',
    'Pop',
    'R&B',
    'Electronic',
    'Reggae',
    'Playing an instrument',
    'Singing',
  ],
  'Tech': [
    'Programming',
    'Mobile apps',
    'Web design',
    'AI & machine learning',
    'Cybersecurity',
    'Robotics',
    'Electronics',
    'Open source',
    'Startups',
    '3D printing',
  ],
  'Creative': [
    'Graphic design',
    'Fashion',
    'Film-making',
    'Animation',
    'Music production',
    'Poetry',
    'Crafts',
    'Interior design',
  ],
  'Outdoors': [
    'Hiking',
    'Camping',
    'Fishing',
    'Travel',
    'Road trips',
    'Birdwatching',
    'Wildlife',
    'Beach days',
  ],
  'Food & drink': [
    'Baking',
    'Street food',
    'Coffee',
    'Tea',
    'Vegan cooking',
    'Barbecue',
    'Trying new restaurants',
  ],
  'Learning & life': [
    'Languages',
    'History',
    'Science',
    'Mathematics',
    'Philosophy',
    'Personal finance',
    'Entrepreneurship',
    'Volunteering',
    'Meditation',
    'Self-improvement',
  ],
};

const interestCategoryIcons = <String, IconData>{
  'Sports': Icons.sports_soccer_outlined,
  'Hobbies': Icons.auto_awesome_outlined,
  'Entertainment': Icons.movie_outlined,
  'Music': Icons.music_note_outlined,
  'Tech': Icons.memory_outlined,
  'Creative': Icons.brush_outlined,
  'Outdoors': Icons.terrain_outlined,
  'Food & drink': Icons.restaurant_outlined,
  'Learning & life': Icons.school_outlined,
};

/// Upper bound on interests per profile, so a profile stays readable.
const maxInterests = 30;
const maxInterestLength = 30;

/// Cleans a custom interest: trims, collapses spaces, caps the length.
/// Returns null when nothing usable is left.
String? cleanInterest(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return null;
  return cleaned.length > maxInterestLength
      ? cleaned.substring(0, maxInterestLength).trimRight()
      : cleaned;
}

/// True if [candidate] is already in [selected], ignoring case.
bool hasInterest(Iterable<String> selected, String candidate) {
  final key = candidate.toLowerCase();
  return selected.any((s) => s.toLowerCase() == key);
}
