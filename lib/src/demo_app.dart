import 'package:flutter/material.dart';
import 'design.dart';
import 'translation.dart';
import 'guide.dart';

class SignBridgeApp extends StatelessWidget {
  const SignBridgeApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'SignBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          primaryColor: primary,
          scaffoldBackgroundColor: canvas,
          colorScheme: const ColorScheme.light(
              primary: primary,
              secondary: green,
              surface: Colors.white,
              background: canvas,
              onBackground: ink,
              onSurface: ink),
          textTheme: ThemeData.light()
              .textTheme
              .apply(bodyColor: ink, displayColor: ink),
          appBarTheme: const AppBarTheme(
              backgroundColor: canvas, foregroundColor: primary, elevation: 0),
          dividerColor: pale),
      home: const DemoHome());
}

class HistoryEntry {
  HistoryEntry(this.command, this.time);
  final String command;
  final DateTime time;
  String get timestamp {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}.${two(time.month)}.${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({Key? key}) : super(key: key);
  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  int tab = 0;
  bool sos = false;
  bool notifications = true;
  bool developerMode = false;
  bool saveHistory = true;
  final devices = <String, bool>{
    '내 스마트폰': true,
    '스마트링': false,
    '무선 이어폰': false,
    '스마트워치': true
  };
  final history = <HistoryEntry>[
    HistoryEntry('전화 끊어줘', DateTime(2024, 3, 20, 14, 30)),
    HistoryEntry('이어폰 음악 재생', DateTime(2024, 3, 20, 12, 15)),
    HistoryEntry('스마트링 연결', DateTime(2024, 3, 19, 20, 5)),
    HistoryEntry('워치 알림 확인', DateTime(2024, 3, 19, 19, 40)),
  ];
  void openGuide() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GuidePage(onTab: navigateTab)));
  void navigateTab(int value) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => tab = value);
  }

  void message(String title, String body) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('확인'))
              ]));

  Future<void> startTranslation() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => TranslationPage(
            sos: sos, onTab: navigateTab, developerMode: developerMode)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Row(children: [
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: primary, borderRadius: BorderRadius.circular(12)),
                child:
                    const Icon(Icons.pan_tool, color: Colors.white, size: 22)),
            const SizedBox(width: 10),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(tab == 2 ? '사용 기록' : 'SignBridge',
                        style: const TextStyle(fontWeight: FontWeight.w700))))
          ]),
          actions: [
            Builder(
                builder: (context) => IconButton(
                    tooltip: '메뉴',
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openEndDrawer())),
            IconButton(
                tooltip: '프로필 설정',
                icon: const Icon(Icons.account_circle),
                onPressed: () => setState(() => tab = 3)),
            const SizedBox(width: 6)
          ]),
      endDrawer: menu(),
      body: SafeArea(
          top: false,
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Stack(
                      children: [
                    home(),
                    devicePage(),
                    historyPage(),
                    settingsPage()
                  ]
                          .asMap()
                          .entries
                          .map((entry) => Offstage(
                              offstage: tab != entry.key, child: entry.value))
                          .toList())))),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: tab,
          onTap: (value) => setState(() => tab = value),
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
          ]));

  Widget home() =>
      ListView(primary: false, padding: const EdgeInsets.all(16), children: [
        const Align(
            alignment: Alignment.centerLeft,
            child:
                Badge('AI 전면 카메라 감지 대기 중', icon: Icons.videocam, color: green)),
        const SizedBox(height: 12),
        const Text('안녕하세요, 서연님 👋',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        description('어떤 수화를 실시간으로 인식할까요?'),
        gap,
        modeCard(
            false, '스마트 기기 제어', '스마트폰과 웨어러블을 연결하는 일상', Icons.devices, const [
          Badge('전화 끊기', icon: Icons.call_end),
          Badge('스마트링', icon: Icons.radio_button_unchecked),
          Badge('이어폰 · 워치', icon: Icons.watch)
        ]),
        gap,
        modeCard(true, '단축키 실행', '숫자 수어 1~9로 기능 실행', Icons.apps, const [
          Badge('1~3 긴급 전화', icon: Icons.phone_in_talk, color: danger),
          Badge('4 앱 · 5 번역', icon: Icons.apps),
          Badge('6 메시지 · 7 타이머', icon: Icons.timer_outlined)
        ]),
        const SizedBox(height: 28),
        PrimaryButton('수화 번역 카메라 시작', startTranslation,
            icon: Icons.camera_alt_outlined, color: primary),
        const SizedBox(height: 12),
        const Text('인식된 수어로 기능을 실행합니다. 현재 번역 모델은 개발 중입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted))
      ]);

  Widget modeCard(bool emergency, String title, String subtitle, IconData icon,
      List<Widget> tags) {
    final selected = sos == emergency;
    const color = primary;
    return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => sos = emergency),
            child: Panel(
                color: selected ? color.withOpacity(.035) : Colors.white,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(icon, color: Colors.white, size: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(subtitle,
                                  style: const TextStyle(
                                      fontSize: 12, color: muted))
                            ])),
                        Icon(selected ? Icons.check_circle : Icons.circle,
                            color: selected ? color : pale, size: 28)
                      ]),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: tags),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: emergency
                              ? () => message('단축키 안내',
                                  '1: 112 신고\n2: 119 신고\n3: 등록된 번호로 전화\n4: 배달의민족 앱 열기\n5: 한국어 입력 후 영어 번역\n6: 등록된 번호로 메시지\n7: 수어로 타이머 설정\n8~9: 미정 · 기능 준비 중\n\n112·119는 전화 앱의 발신 화면에서 확인합니다.')
                              : openGuide,
                          child: Row(children: [
                            Icon(emergency ? Icons.apps : Icons.help_outline,
                                size: 16, color: color),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    emergency ? '1~9번 기능 안내' : '사용 가능한 제스처 보기',
                                    style: const TextStyle(
                                        color: color, fontSize: 12))),
                            const Icon(Icons.chevron_right, color: color)
                          ]))
                    ]))));
  }

  Widget devicePage() =>
      ListView(primary: false, padding: const EdgeInsets.all(20), children: [
        heading('연결된 기기'),
        description('손짓으로 더 편리해지는 일상'),
        gap,
        const Badge('가상 기기 · 데모 연결', icon: Icons.bluetooth_connected),
        gap,
        ...devices.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
                child: Row(children: [
              Icon(
                  entry.key == '내 스마트폰'
                      ? Icons.phone_android
                      : entry.key == '무선 이어폰'
                          ? Icons.headset
                          : entry.key == '스마트워치'
                              ? Icons.watch
                              : Icons.radio_button_unchecked,
                  color: primary,
                  size: 30),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(entry.key,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(entry.value ? '연결됨 · 데모' : '연결 안 됨',
                        style: const TextStyle(color: muted))
                  ])),
              Switch(
                  value: entry.value,
                  activeColor: primary,
                  onChanged: (value) =>
                      setState(() => devices[entry.key] = value))
            ])))),
        OutlinedButton.icon(
            onPressed: () =>
                message('기기 추가', '데모 기기 4개가 준비되어 있습니다. 실제 기기 연결은 추후 지원 예정입니다.'),
            icon: const Icon(Icons.add),
            label: const Padding(
                padding: EdgeInsets.all(16), child: Text('기기 추가')))
      ]);

  Widget historyPage() =>
      ListView(primary: false, padding: const EdgeInsets.all(16), children: [
        if (history.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(children: [
                const Icon(Icons.history, size: 56, color: primary),
                gap,
                heading('아직 사용 기록이 없어요'),
                description('수화 번역을 시작해 보세요.')
              ])),
        ...history.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
                onTap: () => message(entry.command,
                    '${entry.timestamp}\n데모 명령 실행 완료\n실제 기기 제어는 수행하지 않았습니다.'),
                borderRadius: BorderRadius.circular(18),
                child: Panel(
                    child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(entry.command,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(entry.timestamp,
                            style: const TextStyle(color: muted, fontSize: 13))
                      ])),
                  const CircleAvatar(
                      backgroundColor: Color(0xFFE3F0EC),
                      child: Icon(Icons.check_circle, color: green))
                ])))))
      ]);

  Widget settingsPage() =>
      ListView(primary: false, padding: const EdgeInsets.all(20), children: [
        heading('설정'),
        gap,
        const Panel(
            child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Icon(Icons.person)),
                title: Text('서연님'),
                subtitle: Text('SignBridge 데모 사용자'))),
        gap,
        Panel(
            child: Column(children: [
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('개발자 모드'),
              subtitle: const Text('번호 버튼으로 실제 기능 실행을 테스트합니다'),
              value: developerMode,
              onChanged: (v) => setState(() => developerMode = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('알림 표시'),
              subtitle: const Text('앱 내 데모 알림 설정'),
              value: notifications,
              onChanged: (v) => setState(() => notifications = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('사용 기록 저장'),
              subtitle: const Text('앱 실행 중 번역 기록을 보관합니다'),
              value: saveHistory,
              onChanged: (v) => setState(() => saveHistory = v))
        ])),
        gap,
        Panel(
            child: Column(children: [
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline, color: primary),
              title: const Text('서비스 안내'),
              trailing: const Icon(Icons.chevron_right),
              onTap: openGuide),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: danger),
              title: const Text('사용 기록 지우기'),
              onTap: clearHistory),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('앱 버전'),
              trailing: Text('1.0.0 Demo'))
        ])),
        gap,
        description(
            'SignBridge는 수화로 일상과 연결되는 AI 비서입니다. 현재 버전에서는 화면과 메뉴를 체험할 수 있습니다. 설정과 기록은 앱을 종료하면 초기화됩니다.')
      ]);

  Future<void> clearHistory() async {
    final clear = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('사용 기록을 지울까요?'),
                content: const Text('현재 데모의 모든 사용 기록이 삭제됩니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('삭제'))
                ]));
    if (clear == true && mounted) setState(history.clear);
  }

  Widget menu() => Drawer(
          child: SafeArea(
              child: ListView(primary: false, children: [
        Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const CircleAvatar(
                  radius: 26,
                  backgroundColor: pale,
                  child: Icon(Icons.person, color: primary)),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('서연님\n데모 사용자',
                      style:
                          TextStyle(height: 1.7, fontWeight: FontWeight.w600))),
              IconButton(
                  tooltip: '메뉴 닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close))
            ])),
        const Divider(),
        menuItem(Icons.person_outline, '프로필 설정', () => setState(() => tab = 3)),
        menuItem(Icons.info_outline, '서비스 안내', openGuide),
        menuItem(
            Icons.campaign_outlined,
            '공지사항',
            () => message('공지사항',
                'SignBridge 데모에 오신 것을 환영합니다.\n수화 번역 및 기기 제어 기능은 준비 중입니다.')),
        menuItem(Icons.people_outline, '커뮤니티',
            () => message('커뮤니티', '사용 경험을 나누는 커뮤니티를 준비 중입니다.')),
        menuItem(Icons.support_agent, '고객센터',
            () => message('고객센터', '메뉴의 서비스 안내에서 동작 가이드를 확인할 수 있습니다.')),
        const Divider(),
        menuItem(Icons.logout, '로그아웃',
            () => message('데모 계정', '현재 데모 계정으로 사용 중이며 별도의 로그인은 필요하지 않습니다.')),
        gap
      ])));
  Widget menuItem(IconData icon, String text, VoidCallback action) => ListTile(
      leading: Icon(icon, color: primary),
      title: Text(text),
      onTap: () {
        Navigator.pop(context);
        action();
      });
}
