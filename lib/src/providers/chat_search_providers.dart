import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';
import 'package:serafim/src/data/models/public_user.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/providers/local_db_providers.dart';
import 'package:serafim/src/providers/social_providers.dart';

/// A message that matched a chat search, with the person it was exchanged with.
class MessageHit {
  const MessageHit({required this.message, required this.person});

  final LocalMessage message;
  final PublicUser person;
}

class ChatSearchResults {
  const ChatSearchResults({this.people = const [], this.messages = const []});

  /// Conversations whose person matches by name or username.
  final List<PublicUser> people;

  /// Individual messages whose text matches.
  final List<MessageHit> messages;

  bool get isEmpty => people.isEmpty && messages.isEmpty;
}

bool _matches(PublicUser u, String needle) =>
    u.displayName.toLowerCase().contains(needle) ||
    u.username.toLowerCase().contains(needle);

/// Searches the people you chat with and the text of your messages. Everything
/// is local except looking up the profile of someone you have messaged but are
/// not friends with.
final chatSearchProvider = FutureProvider.autoDispose
    .family<ChatSearchResults, String>((ref, query) async {
      final needle = query.trim().toLowerCase();
      final myId = ref.watch(currentAccountIdProvider);
      if (needle.isEmpty || myId == null) return const ChatSearchResults();

      final friends = await ref.watch(friendsProvider.future);
      final peerIds = await ref.watch(conversationPeerIdsProvider.future);

      // Everyone I talk to: friends plus anyone I have messaged.
      final byId = {for (final f in friends) f.id: f};
      for (final id in peerIds) {
        if (byId.containsKey(id)) continue;
        try {
          byId[id] = await ref.watch(publicUserProvider(id).future);
        } catch (_) {
          // A profile we can't load can still be searched by message text.
        }
      }

      final people = byId.values.where((u) => _matches(u, needle)).toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

      final found = await ref
          .read(isarServiceProvider)
          .searchMessages(needle, myId);
      final hits = <MessageHit>[];
      for (final m in found) {
        final otherId = m.senderId == myId ? m.recipientId : m.senderId;
        final person = byId[otherId];
        if (person != null) hits.add(MessageHit(message: m, person: person));
      }

      return ChatSearchResults(people: people, messages: hits);
    });
