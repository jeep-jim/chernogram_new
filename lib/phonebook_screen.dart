import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const String _cernogramInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';

class CgPhonebookScreen extends StatefulWidget {
  final bool ru;

  const CgPhonebookScreen({super.key, required this.ru});

  @override
  State<CgPhonebookScreen> createState() => _CgPhonebookScreenState();
}

class _CgPhonebookScreenState extends State<CgPhonebookScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final FocusNode _numberFocus = FocusNode(debugLabel: 'phone-number');

  List<Contact> _contacts = const <Contact>[];
  bool _loading = false;
  bool _loaded = false;
  bool _permissionDenied = false;
  String _query = '';

  bool get _deviceContactsSupported => Platform.isAndroid || Platform.isIOS;

  @override
  void dispose() {
    _searchController.dispose();
    _numberController.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (!_deviceContactsSupported || _loading) return;
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    try {
      final allowed = await FlutterContacts.requestPermission(readonly: true);
      if (!allowed) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _loaded = false;
          });
        }
        return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      contacts.removeWhere((contact) => contact.phones.isEmpty);
      contacts.sort((left, right) {
        final leftName = left.displayName.trim().toLowerCase();
        final rightName = right.displayName.trim().toLowerCase();
        return leftName.compareTo(rightName);
      });
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Не удалось открыть телефонную книгу.'
                : 'Could not open the phone book.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _normalizedPhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final plus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return '${plus ? '+' : ''}$digits';
  }

  Future<void> _dial(String rawNumber) async {
    final number = _normalizedPhone(rawNumber);
    if (number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) _showDialUnavailable();
    } catch (_) {
      if (mounted) _showDialUnavailable();
    }
  }

  void _showDialUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'На этом устройстве не найдено приложение для телефонных звонков.'
              : 'No phone dialer is available on this device.',
        ),
      ),
    );
  }

  Future<void> _shareInvite(Contact contact, String number) async {
    final name = contact.displayName.trim();
    await Share.share(
      widget.ru
          ? '${name.isEmpty ? 'Приглашение' : name}, установите Cernogram для защищённых сообщений и звонков:\n$_cernogramInstallUrl\n\nНомер: $number'
          : '${name.isEmpty ? 'Invitation' : name}, install Cernogram for secure messages and calls:\n$_cernogramInstallUrl\n\nPhone: $number',
    );
  }

  List<Contact> get _visibleContacts {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    final normalizedQuery = _normalizedPhone(query);
    return _contacts.where((contact) {
      if (contact.displayName.toLowerCase().contains(query)) return true;
      return contact.phones.any((phone) {
        final number = phone.number.toLowerCase();
        return number.contains(query) ||
            (normalizedQuery.isNotEmpty &&
                _normalizedPhone(number).contains(normalizedQuery));
      });
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleContacts;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Телефонная книга' : 'Phone book'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _numberController,
                    focusNode: _numberFocus,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+()\-\s]'),
                      ),
                    ],
                    onSubmitted: _dial,
                    decoration: InputDecoration(
                      labelText: widget.ru ? 'Номер телефона' : 'Phone number',
                      hintText: '+7 900 000-00-00',
                      prefixIcon: const Icon(Icons.dialpad_rounded),
                      suffixIcon: IconButton(
                        tooltip: widget.ru ? 'Позвонить' : 'Call',
                        onPressed: () => _dial(_numberController.text),
                        icon: const Icon(Icons.call_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_loaded)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _deviceContactsSupported && !_loading
                            ? _loadContacts
                            : null,
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.contacts_rounded),
                        label: Text(
                          _deviceContactsSupported
                              ? (widget.ru
                                  ? 'Открыть контакты телефона'
                                  : 'Open device contacts')
                              : (widget.ru
                                  ? 'Контакты устройства доступны на Android'
                                  : 'Device contacts are available on Android'),
                        ),
                      ),
                    ),
                  if (_permissionDenied)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.ru
                            ? 'Доступ не предоставлен. Cernogram не читает телефонную книгу без вашего разрешения.'
                            : 'Permission was not granted. Cernogram never reads the phone book without your consent.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (_loaded) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: widget.ru
                            ? 'Поиск по имени или номеру'
                            : 'Search by name or number',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          widget.ru
                              ? 'Можно набрать номер вручную или открыть телефонную книгу. Контакты загружаются только в память и не публикуются.'
                              : 'Enter a number manually or open the phone book. Contacts are loaded only into memory and are never published.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: .58),
                          ),
                        ),
                      ),
                    )
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                            widget.ru
                                ? 'Контакты с номерами не найдены'
                                : 'No contacts with phone numbers found',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 24),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final contact = visible[index];
                            return _PhoneContactCard(
                              contact: contact,
                              ru: widget.ru,
                              onDial: _dial,
                              onInvite: _shareInvite,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneContactCard extends StatelessWidget {
  final Contact contact;
  final bool ru;
  final Future<void> Function(String number) onDial;
  final Future<void> Function(Contact contact, String number) onInvite;

  const _PhoneContactCard({
    required this.contact,
    required this.ru,
    required this.onDial,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final name = contact.displayName.trim();
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(letter)),
        title: Text(
          name.isEmpty ? (ru ? 'Без имени' : 'Unnamed') : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          contact.phones.first.number,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          for (final phone in contact.phones)
            ListTile(
              dense: true,
              leading: const Icon(Icons.phone_outlined),
              title: SelectableText(phone.number),
              trailing: Wrap(
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: ru ? 'Пригласить в Cernogram' : 'Invite to Cernogram',
                    onPressed: () => onInvite(contact, phone.number),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                  IconButton.filled(
                    tooltip: ru ? 'Позвонить через телефон' : 'Call with phone',
                    onPressed: () => onDial(phone.number),
                    icon: const Icon(Icons.call_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
