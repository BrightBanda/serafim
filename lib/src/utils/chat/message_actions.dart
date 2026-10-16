enum MessageAction { copy, download, edit, delete }

/// Which long-press actions apply to a message. Kept free of widgets so the
/// ownership and attachment rules can be unit tested.
///
/// - Only the sender can edit; only text can be edited, and only once the
///   server has accepted it.
/// - Anyone can delete a message from their own device ("delete for me"); the
///   delete dialog additionally offers "delete for everyone" for the
///   sender's own messages (see [deleteOptionsFor]).
/// - A message deleted for everyone can only be cleared from this device.
List<MessageAction> availableMessageActions({
  required bool isOutgoing,
  required bool isDeleted,
  required bool hasText,
  required bool isImage,
  required bool isConfirmed,
}) {
  if (isDeleted) return const [MessageAction.delete];
  return [
    if (hasText) MessageAction.copy,
    if (isImage) MessageAction.download,
    if (isOutgoing && !isImage && isConfirmed) MessageAction.edit,
    MessageAction.delete,
  ];
}

/// The choices the delete dialog offers for a message.
class DeleteOptions {
  const DeleteOptions({required this.forMe, required this.forEveryone});

  /// Remove it from this device only.
  final bool forMe;

  /// Remove it for everyone in the conversation: the sender's own messages
  /// that the server has accepted and that are not already deleted.
  final bool forEveryone;
}

DeleteOptions deleteOptionsFor({
  required bool isOutgoing,
  required bool isDeleted,
  required bool isConfirmed,
}) {
  return DeleteOptions(
    forMe: true,
    forEveryone: isOutgoing && isConfirmed && !isDeleted,
  );
}
