import 'package:flutter/widgets.dart';
import 'package:password_manager/main.dart';

/// Screenshot-only demo: no VaultStore, no real file access or persistence.
void main() => runApp(const PasswordManagerApp(demo: true));
