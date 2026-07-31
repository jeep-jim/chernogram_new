from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "lib" / "android_data_first.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    text = PATH.read_text(encoding="utf-8")

    old_forward = """    final updated = target.copyWith(messages: [...target.messages, forwarded]);
    _updateTunnel(updated);
    await ChernogramAppMonitor.publishMessage(
      profile: profile,
      tunnel: updated,
      message: forwarded,
    );
    _showMessage(widget.ru ? 'Сообщение переслано.' : 'Message forwarded.');
"""
    new_forward = """    final updated = target.copyWith(messages: [...target.messages, forwarded]);
    _updateTunnel(updated);
    var networkForwarded = forwarded;
    final attachment = forwarded.attachment;
    if (attachment != null) {
      final file = await CgMediaStore.ensureFile(attachment);
      if (file != null) {
        final bytes = await file.readAsBytes();
        networkForwarded = forwarded.copyWith(
          attachment: CgAttachment(
            id: attachment.id,
            name: attachment.name,
            size: bytes.length,
            kind: attachment.kind,
            dataBase64: base64Encode(bytes),
            localPath: file.path,
          ),
        );
      }
    }
    unawaited(
      ChernogramAppMonitor.publishMessage(
        profile: profile,
        tunnel: updated,
        message: networkForwarded,
      ),
    );
    _showMessage(widget.ru ? 'Сообщение переслано.' : 'Message forwarded.');
"""
    text = replace_once(text, old_forward, new_forward, "forward file payload")

    old_publish = """      final attachment = CgAttachment(
        id: CgIds.random(20),
        name: picked.name,
        size: bytes.length,
        kind: _kind(picked.name),
        dataBase64: base64Encode(bytes),
        localPath: picked.path,
      );
      final message = CgMessage(
        id: CgIds.random(24),
        authorId: widget.profile.id,
        authorName: widget.profile.nickname,
        text: '',
        sentAt: DateTime.now(),
        type: 'attachment',
        attachment: attachment,
        meta: const {'publicFile': true, 'indexed': true},
      );
      final updated = room.copyWith(messages: [...room.messages, message]);
      widget.onTunnelChanged(updated);
      await ChernogramAppMonitor.publishMessage(
        profile: widget.profile,
        tunnel: updated,
        message: message,
      );
"""
    new_publish = """      final attachmentId = CgIds.random(20);
      final localFile = await CgMediaStore.persistBytes(
        attachmentId: attachmentId,
        name: picked.name,
        bytes: bytes,
      );
      final sentAt = DateTime.now();
      final messageId = CgIds.random(24);
      final localMessage = CgMessage(
        id: messageId,
        authorId: widget.profile.id,
        authorName: widget.profile.nickname,
        text: '',
        sentAt: sentAt,
        type: 'attachment',
        attachment: CgAttachment(
          id: attachmentId,
          name: picked.name,
          size: bytes.length,
          kind: _kind(picked.name),
          localPath: localFile.path,
        ),
        meta: const {
          'publicFile': true,
          'indexed': true,
          'fileReady': true,
        },
      );
      final networkMessage = CgMessage(
        id: messageId,
        authorId: widget.profile.id,
        authorName: widget.profile.nickname,
        text: '',
        sentAt: sentAt,
        type: 'attachment',
        attachment: CgAttachment(
          id: attachmentId,
          name: picked.name,
          size: bytes.length,
          kind: _kind(picked.name),
          dataBase64: base64Encode(bytes),
          localPath: localFile.path,
        ),
        meta: const {'publicFile': true, 'indexed': true},
      );
      final updated = room.copyWith(
        messages: [...room.messages, localMessage],
      );
      widget.onTunnelChanged(updated);
      unawaited(
        ChernogramAppMonitor.publishMessage(
          profile: widget.profile,
          tunnel: updated,
          message: networkMessage,
        ),
      );
"""
    text = replace_once(text, old_publish, new_publish, "public file publish")

    old_materialize = """  Future<File?> _materialize(CgAttachment attachment) async {
    final path = attachment.localPath;
    if (path != null && await File(path).exists()) return File(path);
    final raw = attachment.dataBase64;
    if (raw == null) return null;
    final directory = await getTemporaryDirectory();
    final safeName = attachment.name.replaceAll(
      RegExp(r'[^A-Za-zА-Яа-я0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/${attachment.id}_$safeName');
    await file.writeAsBytes(base64Decode(raw), flush: true);
    return file;
  }
"""
    new_materialize = """  Future<File?> _materialize(CgAttachment attachment) =>
      CgMediaStore.ensureFile(attachment);
"""
    text = replace_once(text, old_materialize, new_materialize, "shared file store")

    PATH.write_text(text, encoding="utf-8")
    print("Files-first local/network payload split finalized")


if __name__ == "__main__":
    main()
