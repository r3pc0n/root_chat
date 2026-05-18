import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/storage_service.dart';
import 'screens/chat_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  runApp(RootChatApp(storage: storage));
}

class RootChatApp extends StatefulWidget {
  final StorageService storage;
  const RootChatApp({super.key, required this.storage});

  @override
  State<RootChatApp> createState() => _RootChatAppState();
}

class _RootChatAppState extends State<RootChatApp> {
  late final ValueNotifier<AppThemeData> _themeNotifier;

  @override
  void initState() {
    super.initState();
    _themeNotifier = ValueNotifier(AppThemeData.fromKey(widget.storage.themeMode));
    _themeNotifier.addListener(_onThemeChanged);
    _applySystemUi(_themeNotifier.value);
  }

  void _onThemeChanged() {
    widget.storage.setThemeMode(_themeNotifier.value.key);
    _applySystemUi(_themeNotifier.value);
    setState(() {});
  }

  void _applySystemUi(AppThemeData t) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: t.surface,
      statusBarIconBrightness: t.isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: t.bg,
      systemNavigationBarIconBrightness: t.isLight ? Brightness.dark : Brightness.light,
    ));
  }

  @override
  void dispose() {
    _themeNotifier.removeListener(_onThemeChanged);
    _themeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _themeNotifier.value;
    return AppTheme(
      data: t,
      notifier: _themeNotifier,
      child: MaterialApp(
        title: 'root_chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: t.isLight ? Brightness.light : Brightness.dark,
          colorScheme: ColorScheme(
            brightness: t.isLight ? Brightness.light : Brightness.dark,
            primary: t.amber,
            onPrimary: t.bg,
            secondary: t.green,
            onSecondary: t.bg,
            surface: t.surface,
            onSurface: t.body,
            error: t.red,
            onError: t.bg,
          ),
          scaffoldBackgroundColor: t.bg,
          textTheme: GoogleFonts.jetBrainsMonoTextTheme(
            t.isLight ? ThemeData.light().textTheme : ThemeData.dark().textTheme,
          ),
        ),
        home: widget.storage.username.isEmpty
            ? _UsernameGate(storage: widget.storage)
            : ChatScreen(storage: widget.storage),
      ),
    );
  }
}

// ── username gate (first launch) ─────────────────────────────────────────────
class _UsernameGate extends StatefulWidget {
  final StorageService storage;
  const _UsernameGate({required this.storage});

  @override
  State<_UsernameGate> createState() => _UsernameGateState();
}

class _UsernameGateState extends State<_UsernameGate> {
  final _ctrl = TextEditingController();

  Future<void> _confirm() async {
    final val = _ctrl.text.trim();
    if (val.isEmpty) return;
    await widget.storage.setUsername(val);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ChatScreen(storage: widget.storage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final mono = GoogleFonts.jetBrainsMono;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('root_chat',
                  style: mono(fontSize: 20, color: t.body, fontWeight: FontWeight.w400)),
              const SizedBox(height: 4),
              Text('relay  ·  public room',
                  style: mono(fontSize: 13, color: t.sys)),
              const SizedBox(height: 40),
              Container(
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.saved))),
                child: Row(
                  children: [
                    Text('> ', style: mono(fontSize: 14, color: t.dim)),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        style: mono(fontSize: 14, color: t.body),
                        cursorColor: t.own,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'choose a username',
                          hintStyle: mono(fontSize: 14, color: t.subtle),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onSubmitted: (_) => _confirm(),
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('enter to connect',
                  style: mono(fontSize: 12, color: t.subtle)),
            ],
          ),
        ),
      ),
    );
  }
}
