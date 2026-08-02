from pathlib import Path
import re

path = Path('lib/light/light_chat_app.dart')
text = path.read_text(encoding='utf-8')

pages_pattern = re.compile(
    r"    final pages = <Widget>\[\n"
    r"      _DialerPage\(.*?\n"
    r"      \),\n"
    r"      _ChatsPage\(",
    re.DOTALL,
)
pages_replacement = """    final pages = <Widget>[
      _ContactsHomePage(
        contacts: _knownContacts,
        chats: _chats,
        onInvite: _newChat,
        onOpenChat: _openChat,
        onKnownContact: _openKnownContact,
      ),
      _ChatsPage("""
text, count = pages_pattern.subn(pages_replacement, text, count=1)
if count != 1:
    raise RuntimeError('Could not replace dialer page in pages list')

old_destination = """              NavigationDestination(
                icon: Icon(Icons.dialpad_outlined),
                selectedIcon: Icon(Icons.dialpad_rounded),
                label: 'Звонки',
              ),"""
new_destination = """              NavigationDestination(
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Контакты',
              ),"""
if old_destination not in text:
    raise RuntimeError('Could not find dialer navigation destination')
text = text.replace(old_destination, new_destination, 1)

contacts_page = r'''class _ContactsHomePage extends StatefulWidget {
  final List<CgContact> contacts;
  final List<CgTunnel> chats;
  final Future<void> Function() onInvite;
  final Future<void> Function(CgTunnel chat, {String initialAction}) onOpenChat;
  final Future<void> Function(CgContact contact, String action) onKnownContact;

  const _ContactsHomePage({
    required this.contacts,
    required this.chats,
    required this.onInvite,
    required this.onOpenChat,
    required this.onKnownContact,
  });

  @override
  State<_ContactsHomePage> createState() => _ContactsHomePageState();
}

class _ContactsHomePageState extends State<_ContactsHomePage> {
  final TextEditingController _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final contacts = widget.contacts.where((contact) {
      if (query.isEmpty) return true;
      return contact.nickname.toLowerCase().contains(query);
    }).toList();
    final recentChats = widget.chats.take(5).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PageHeader(
              title: 'Контакты',
              subtitle: 'Только реальные контакты Чернограма',
              trailing: IconButton.filled(
                tooltip: 'Пригласить человека',
                onPressed: widget.onInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Найти контакт',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: LightGlass(
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(26),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: LightChatColors.violet.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.link_rounded),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Добавить человека',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Выбери контакт телефона и отправь ему защищённую ссылку. После принятия появятся чат и звонки.',
                            style: TextStyle(fontSize: 11.5, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: widget.onInvite,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Люди в Чернограме',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (contacts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: LightGlass(
                  padding: const EdgeInsets.all(20),
                  borderRadius: BorderRadius.circular(26),
                  child: Column(
                    children: [
                      const Icon(Icons.people_outline_rounded, size: 46),
                      const SizedBox(height: 10),
                      Text(
                        query.isEmpty
                            ? 'Контактов Чернограма пока нет'
                            : 'Контакт не найден',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        query.isEmpty
                            ? 'Пригласи человека один раз — контакт и диалог сохранятся.'
                            : 'Измени запрос или очисти поиск.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .58),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
              sliver: SliverList.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: LightGlass(
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(26),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 6, 5, 6),
                        leading: ChernogramAvatar(
                          size: 50,
                          seed: contact.id,
                          avatarBase64: contact.avatarBase64,
                        ),
                        title: Text(
                          contact.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: const Text('Контакт Чернограма'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Написать',
                              onPressed: () =>
                                  widget.onKnownContact(contact, 'chat'),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Аудиозвонок',
                              onPressed: () =>
                                  widget.onKnownContact(contact, 'audio'),
                              icon: const Icon(Icons.call_outlined),
                            ),
                            IconButton(
                              tooltip: 'Видеозвонок',
                              onPressed: () =>
                                  widget.onKnownContact(contact, 'video'),
                              icon: const Icon(Icons.videocam_outlined),
                            ),
                          ],
                        ),
                        onTap: () => widget.onKnownContact(contact, 'chat'),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (recentChats.isNotEmpty) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Последние диалоги',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 110),
              sliver: SliverList.builder(
                itemCount: recentChats.length,
                itemBuilder: (context, index) {
                  final chat = recentChats[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: LightGlass(
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(26),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                        leading: ChernogramAvatar(
                          size: 48,
                          seed: chat.id,
                          avatarBase64: chat.avatarBase64,
                        ),
                        title: Text(
                          chat.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          chat.messages.isEmpty
                              ? 'Открыть диалог'
                              : chat.messages.last.text.trim().isEmpty
                                  ? 'Вложение или звонок'
                                  : chat.messages.last.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                        onTap: () => widget.onOpenChat(chat),
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

'''

class_pattern = re.compile(
    r'class _DialerPage extends StatelessWidget \{.*?\nclass _ChatsPage extends StatefulWidget \{',
    re.DOTALL,
)
text, count = class_pattern.subn(
    contacts_page + 'class _ChatsPage extends StatefulWidget {',
    text,
    count=1,
)
if count != 1:
    raise RuntimeError('Could not replace dialer classes')

path.write_text(text, encoding='utf-8')
print('Fake dialer removed; contacts-first home installed.')
