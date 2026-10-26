import 'dart:math';
import 'dart:convert';

class AccountEntry {
  AccountEntry(
    this.name,
    this.username,
    this.password,
    this.url,
    this.notes, {
    String? id,
    this.modifiedAt,
    List<AccountEntry> history = const [],
  }) : id = id ?? _newId(),
       history = List.unmodifiable(history);
  final String id, name, username, password, url, notes;
  final DateTime? modifiedAt;
  final List<AccountEntry> history;

  AccountEntry withPrevious(AccountEntry? previous) {
    if (previous != null &&
        name == previous.name &&
        username == previous.username &&
        password == previous.password &&
        url == previous.url &&
        notes == previous.notes) {
      return previous;
    }
    return AccountEntry(
      name,
      username,
      password,
      url,
      notes,
      id: id,
      modifiedAt: DateTime.now().toUtc(),
      history: previous == null
          ? history
          : [
              AccountEntry(
                previous.name,
                previous.username,
                previous.password,
                previous.url,
                previous.notes,
                id: previous.id,
                modifiedAt: previous.modifiedAt,
              ),
              ...previous.history,
            ].take(20).toList(),
    );
  }

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Map<String, String> toMap() => {
    'id': id,
    'name': name,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
    'modifiedAt': modifiedAt?.toIso8601String() ?? '',
    'history': jsonEncode(history.map((entry) => entry.toMap()).toList()),
  };
  factory AccountEntry.fromMap(Map<String, String> value) => AccountEntry(
    value['name']!,
    value['username']!,
    value['password']!,
    value['url']!,
    value['notes']!,
    id: value['id']!,
    modifiedAt: DateTime.tryParse(value['modifiedAt'] ?? ''),
    history: (jsonDecode(value['history'] ?? '[]') as List).take(20).map((
      item,
    ) {
      final snapshot = Map<String, String>.from(item as Map);
      snapshot['history'] = '[]';
      return AccountEntry.fromMap(snapshot);
    }).toList(),
  );
}
