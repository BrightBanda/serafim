enum MessageAction { copy, download, edit, delete, reply, forward, save }

/// Which long-press actions apply to a message. Kept free of widgets so the
/// ownership and attachment rules can be unit tested.
///
/// - Only the sender can edit; only text can be edited, and only once the
///   server has accepted it.
/// - Anyone can delete a message from their own device ("delete for me"); the
///   delete dialog additionally offers "delete for everyone" for the
///   sender's own messages (see [deleteOptionsFor]).
/// - A message deleted for everyone can only be cleared from this device.
/// - Replying to and forwarding both need a message the server has
///   accepted, so they are offered together and never for a message that is
///   still sending, has failed, or has been deleted.
/// - [MessageAction.save] (to a collection) is offered for confirmed
///   stickers, GIFs, videos and audio files.
/// - Videos and audio files ([isFile]) are fetched only when asked, so saving
///   them (to the device or a collection) waits until [fileOnDevice]. They
///   can still be replied to and forwarded before that: forwarding copies
///   them on the server.
List<MessageAction> availableMessageActions({
  required bool isOutgoing,
  required bool isDeleted,
  required bool hasText,
  required bool isImage,
  required bool isGif,
  required bool isSticker,
  required bool isFile,
  required bool fileOnDevice,
  required bool isConfirmed,
}) {
  if (isDeleted) return const [MessageAction.delete];
  final fileReady = isFile && fileOnDevice;
  return [
    if (hasText) MessageAction.copy,
    if (isImage || fileReady) MessageAction.download,
    if (isOutgoing && !isImage && !isFile && isConfirmed) MessageAction.edit,
    if (isConfirmed) ...[MessageAction.reply, MessageAction.forward],
    if ((isSticker || isGif || fileReady) && isConfirmed) MessageAction.save,
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
