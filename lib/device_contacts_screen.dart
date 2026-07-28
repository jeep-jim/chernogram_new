import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

class CgDeviceContactsScreen extends StatefulWidget {
  final bool ru;

  const CgDeviceContactsScreen({super.key, required this.ru});

  @override
  State<CgDeviceContactsScreen> createState() => _CgDeviceContactsScreenState();
}

class _CgDeviceContactsScreenState extends State<CgDeviceContactsScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _number = TextEditingController();
  List<Contact> _contacts = const <Contact>[];
  bool _loading = true;
  bool _permissionDenied = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    _number.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _permissionDenied = false;
      });
    }
    final allowed = await FlutterContacts.requestPermission(readonly: true);
    if (!allowed) {
      if (mounted) {
        setState(() {
          _loading = false;
          _permissionDenied = true;
        });
      }
      return;
    }
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
      withThumbnail: true,
      sorted: true,
    );
    contacts.removeWhere((contact) => contact.phones.isEmpty);
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  List<Contact> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts.where((contact) {
      if (contact.displayName.toLowerCase().contains(query)) return true;
      return contact.phones.any(
        (phone) => _digits(phone.number).contains(_digits(query)),
      );
    }).toList();
  }

  String _digits(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _call(String raw) async {
    final number = _digits(raw);
    if (number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'На устройстве не найдена системная звонилка.'
                : 'No system phone app was found.',
          ),
        ),
      );
    }
  }

  Future<void> _showContact(Contact contact) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ContactAvatar(contact: contact, size: 76),
              const SizedBox(height: 10),
              Text(
                contact.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              for (final phone in contact.phones)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_outlined),
                  title: Text(phone.number),
                  subtitle: phone.label.name.isEmpty
                      ? null
                      : Text(phone.label.name),
                  trailing: IconButton.filled(
                    tooltip: widget.ru ? 'Позвонить' : 'Call',
                    onPressed: () => _call(phone.number),
                    icon: const Icon(Icons.call_rounded),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'Обычный звонок выполняется через системную SIM-звонилку. Звонок через Cernogram появится здесь после возвращения нового Calls Core.'
                    : 'A regular call uses the system SIM phone app. Cernogram calling will appear here after the new Calls Core returns.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _appendDigit(String digit) {
    final next = '${_number.text}$digit';
    _number.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.ru ? 'Телефонная книга' : 'Phone book'),
          actions: [
            IconButton(
              tooltip: widget.ru ? 'Обновить контакты' : 'Refresh contacts',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment<int>(
                  value: 0,
                  icon: const Icon(Icons.contacts_outlined),
                  label: Text(widget.ru ? 'Контакты' : 'Contacts'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: const Icon(Icons.dialpad_rounded),
                  label: Text(widget.ru ? 'Набор номера' : 'Dialer'),
                ),
              ],
              selected: <int>{_tab},
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
        ),
        body: _tab == 0 ? _contactsBody() : _dialerBody(),
      );

  Widget _contactsBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.contacts_outlined, size: 66),
              const SizedBox(height: 12),
              Text(
                widget.ru
                    ? 'Для телефонной книги нужен доступ к контактам.'
                    : 'Contact access is required for the phone book.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(widget.ru ? 'Разрешить' : 'Allow'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: widget.ru ? 'Имя или номер' : 'Name or number',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Expanded(
          child: _visible.isEmpty
              ? Center(
                  child: Text(widget.ru ? 'Контакты не найдены' : 'No contacts found'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 20),
                  itemCount: _visible.length,
                  itemBuilder: (context, index) {
                    final contact = _visible[index];
                    final primary = contact.phones.first.number;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 2),
                      child: ListTile(
                        onTap: () => _showContact(contact),
                        leading: _ContactAvatar(contact: contact, size: 44),
                        title: Text(
                          contact.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: widget.ru ? 'Позвонить' : 'Call',
                          onPressed: () => _call(primary),
                          icon: const Icon(Icons.call_outlined),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _dialerBody() {
    const keys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '0', '⌫'];
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                TextField(
                  controller: _number,
                  autofocus: false,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '+7 900 000 00 00',
                    suffixIcon: IconButton(
                      onPressed: _number.clear,
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                  ),
                  itemCount: keys.length,
                  itemBuilder: (context, index) {
                    final value = keys[index];
                    return FilledButton.tonal(
                      onPressed: value == '⌫'
                          ? () {
                              if (_number.text.isEmpty) return;
                              final next = _number.text.substring(0, _number.text.length - 1);
                              _number.value = TextEditingValue(
                                text: next,
                                selection: TextSelection.collapsed(offset: next.length),
                              );
                            }
                          : () => _appendDigit(value),
                      child: value == '⌫'
                          ? const Icon(Icons.backspace_outlined)
                          : Text(
                              value,
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF28D7A1),
                    fixedSize: const Size.square(68),
                    shape: const CircleBorder(),
                  ),
                  onPressed: _number.text.trim().isEmpty
                      ? null
                      : () => _call(_number.text),
                  icon: const Icon(Icons.call_rounded, size: 34),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactAvatar extends StatelessWidget {
  final Contact contact;
  final double size;

  const _ContactAvatar({required this.contact, required this.size});

  @override
  Widget build(BuildContext context) {
    final photo = contact.thumbnail ?? contact.photo;
    if (photo != null && photo.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          photo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (size * 3).round(),
        ),
      );
    }
    final letter = contact.displayName.trim().isEmpty
        ? '?'
        : contact.displayName.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * .38,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
