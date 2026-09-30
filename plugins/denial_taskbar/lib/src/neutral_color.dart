import 'package:material_ui/material_ui.dart';

Color taskbarForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffeeeeee)
    : const Color(0xff202020);
