import 'package:flutter/material.dart';

const primary = Color(0xFF003D9B);
const canvas = Color(0xFFF9F9FF);
const ink = Color(0xFF041B3C);
const muted = Color(0xFF434654);
const pale = Color(0xFFE8EDFF);
const green = Color(0xFF006844);
const danger = Color(0xFFBA1A1A);
const gap = SizedBox(height: 20);

class Panel extends StatelessWidget {
  const Panel({Key? key, required this.child, this.color = Colors.white})
      : super(key: key);
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9EBF3)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x05041B3C), blurRadius: 8, offset: Offset(0, 3))
          ]),
      child: child);
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, this.onPressed,
      {Key? key, this.icon = Icons.arrow_forward, this.color = primary})
      : super(key: key);
  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              primary: color,
              onPrimary: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              minimumSize: const Size(48, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: onPressed,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon),
            const SizedBox(width: 10),
            Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)))
          ])));
}

class Badge extends StatelessWidget {
  const Badge(this.label,
      {Key? key, this.icon = Icons.check_circle, this.color = primary})
      : super(key: key);
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)))
      ]));
}

Widget heading(String text) => Text(text,
    style: const TextStyle(
        fontSize: 24, fontWeight: FontWeight.w700, height: 1.4));
Widget description(String text) => Text(text,
    style: const TextStyle(color: muted, fontSize: 15, height: 1.65));

class DemoNavigation extends StatelessWidget {
  const DemoNavigation({Key? key, required this.onTap, this.index = 0})
      : super(key: key);
  final ValueChanged<int> onTap;
  final int index;
  @override
  Widget build(BuildContext context) => BottomNavigationBar(
          currentIndex: index,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: primary,
          unselectedItemColor: muted,
          backgroundColor: canvas,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.translate), label: '번역'),
            BottomNavigationBarItem(icon: Icon(Icons.devices), label: '기기'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정')
          ]);
}
