import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/storage_service.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF141414),
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0D0D0D),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final storage = StorageService();
  await storage.init();

  runApp(RootChatApp(storage: storage));
}

class RootChatApp extends StatelessWidget {
  final StorageService storage;
  const RootChatApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'root_chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(surface: Color(0xFF0D0D0D)),
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: storage.username.isEmpty
          ? _UsernameGate(storage: storage)
          : ChatScreen(storage: storage),
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
    final mono = GoogleFonts.jetBrainsMono;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('root_chat',
                  style: mono(fontSize: 20, color: const Color(0xFFCCCCCC), fontWeight: FontWeight.w400)),
              const SizedBox(height: 4),
              Text('relay  ·  public room',
                  style: mono(fontSize: 13, color: const Color(0xFF3A3A3A))),
              const SizedBox(height: 40),
              Container(
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
                child: Row(
                  children: [
                    Text('> ', style: mono(fontSize: 14, color: const Color(0xFF2E2E2E))),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        style: mono(fontSize: 14, color: const Color(0xFF888888)),
                        cursorColor: const Color(0xFF555555),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'choose a username',
                          hintStyle: mono(fontSize: 14, color: const Color(0xFF252525)),
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
                  style: mono(fontSize: 12, color: const Color(0xFF252525))),
            ],
          ),
        ),
      ),
    );
  }
}
