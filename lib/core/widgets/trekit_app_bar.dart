import 'package:flutter/material.dart';

class TrekItAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TrekItAppBar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.backgroundColor,
    this.foregroundColor,
  });

  final Widget title;
  final List<Widget> actions;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final effectiveForeground =
        foregroundColor ?? Theme.of(context).appBarTheme.foregroundColor;
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: canPop ? 94 : 62,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPop)
            BackButton(color: effectiveForeground)
          else
            const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('trekit-t.png', width: 38, height: 38),
          ),
        ],
      ),
      centerTitle: true,
      title: DefaultTextStyle.merge(
        style: TextStyle(
          color: effectiveForeground,
          fontWeight: FontWeight.w800,
        ),
        child: title,
      ),
      actions: actions,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }
}
