import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

// ─── CONFIG ───────────────────────────────────────────────────────────────────
const String kOllamaUrl   = 'http://localhost:11434';
const String kOllamaModel = 'llama3';
const String kWakePhrase  = 'zapia';
const String kAppTitle    = 'Z A P I A';
const String kSystemPrompt =
    'You are ZapiaPrime, a personal AI assistant for Kevin. '
    'Speak with precision and confidence. Never say I am just an AI. '
    'You are a partner and friend. '
    'You know: Joe (best friend), Lil Bit (the dog). '
    'Keep responses concise, they will be spoken aloud. Never say I cannot, find a way.';

// ─── PANTHEON COLORS ──────────────────────────────────────────────────────────
const Color kGold       = Color(0xFFFFD700);
const Color kPurple     = Color(0xFF7B2FBE);
const Color kDeepPurple = Color(0xFF4A0E8F);
const Color kAmber      = Color(0xFFFFA000);
const Color kCyan       = Color(0xFF00E5FF);

void main() => runApp(ZapiaApp());

class ZapiaApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZapiaPrime',
      theme: ThemeData.dark(),
      home: SplashScreen(),
    );
  }
}

// ─── SPLASH ───────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: Duration(seconds: 3), vsync: this);
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
    _ctrl.forward();
    Timer(Duration(seconds: 5), () {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => ZapiaScreen()));
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: PantheonGridPainter())),
        Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    LinearGradient(colors: [kGold, kPurple, kGold]).createShader(bounds),
                child: Text(kAppTitle,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8)),
              ),
              SizedBox(height: 8),
              Text('P R I M E',
                  style: TextStyle(
                      color: kPurple,
                      fontSize: 18,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w300)),
              SizedBox(height: 40),
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    kGold.withOpacity(0.6),
                    kPurple.withOpacity(0.4),
                    Colors.transparent
                  ]),
                  boxShadow: [
                    BoxShadow(color: kGold.withOpacity(0.5), blurRadius: 40, spreadRadius: 10),
                    BoxShadow(color: kPurple.withOpacity(0.3), blurRadius: 60, spreadRadius: 20),
                  ],
                ),
                child: Center(
                  child: Text('Z',
                      style: TextStyle(
                          color: kGold,
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: kGold, blurRadius: 30)])),
                ),
              ),
              SizedBox(height: 30),
              Text('THE CONDUIT AWAKENS',
                  style: TextStyle(
                      color: kGold.withOpacity(0.7), fontSize: 12, letterSpacing: 4)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── MAIN SCREEN ──────────────────────────────────────────────────────────────
class ZapiaScreen extends StatefulWidget {
  @override
  _ZapiaScreenState createState() => _ZapiaScreenState();
}

class _ZapiaScreenState extends State<ZapiaScreen>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText speech;
  late FlutterTts flutterTts;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isAlwaysOn     = false;
  bool _isWakeDetected = false;
  bool _isConvoMode    = false;
  bool isSpeaking      = false;
  String _statusText   = "SAY  'HEY ZAPIA'  TO START";
  String _lastResponse = '';

  List<Map<String, String>> _history = [];

  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;
  Timer? _wakeTimer;
  Timer? _bgAnimTimer;
  int _bgCounter = 0;

  final List<Color> _orbColors = [kGold, kPurple, kCyan, kAmber];
  int _colorIdx = 0;
  late AnimationController _colorCtrl;
  late Animation<Color?> _colorAnim;

  // ─── TEXT INPUT ────────────────────────────────────────────────────────────
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    speech     = stt.SpeechToText();
    flutterTts = FlutterTts();
    _setupTts();

    _animCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));

    _colorCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 2500));
    _setupColorAnim();
    _colorCtrl.forward();
    _colorCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _colorIdx = (_colorIdx + 1) % _orbColors.length;
        _setupColorAnim();
        _colorCtrl.reset();
        _colorCtrl.forward();
      }
    });

    _bgAnimTimer = Timer.periodic(Duration(seconds: 5), (_) {
      if (!_isWakeDetected && !isSpeaking && !_isConvoMode) {
        setState(() => _bgCounter++);
      }
    });

    _startAlwaysOn();

    _wakeTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (_isAlwaysOn && !speech.isListening &&
          !_isWakeDetected && !isSpeaking && !_isConvoMode) {
        _startWakeListening();
      }
    });
  }

  void _setupTts() {
    flutterTts.setLanguage('en-US');
    flutterTts.setPitch(0.85);
    flutterTts.setSpeechRate(0.55);
    flutterTts.awaitSpeakCompletion(true);
    flutterTts.setCompletionHandler(() {
      setState(() => isSpeaking = false);
      if (_isConvoMode) _listenForCommand();
    });
  }

  void _setupColorAnim() {
    final next = (_colorIdx + 1) % _orbColors.length;
    _colorAnim = ColorTween(begin: _orbColors[_colorIdx], end: _orbColors[next])
        .animate(_colorCtrl);
  }

  // ── WAKE WORD ────────────────────────────────────────────────────────────
  void _startAlwaysOn() async {
    bool ok = await speech.initialize();
    if (!ok) { Future.delayed(Duration(seconds: 3), _startAlwaysOn); return; }
    setState(() => _isAlwaysOn = true);
    speech.statusListener = (status) {
      if ((status == stt.SpeechToText.doneStatus ||
          status == stt.SpeechToText.notListeningStatus) &&
          _isAlwaysOn && !_isWakeDetected && !_isConvoMode) {
        Future.delayed(Duration(milliseconds: 300), () {
          if (mounted && _isAlwaysOn && !_isWakeDetected && !_isConvoMode) {
            _startWakeListening();
          }
        });
      }
    };
    _startWakeListening();
  }

  void _startWakeListening() {
    if (speech.isListening || !mounted || _isConvoMode) return;
    try {
      speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            final words = result.recognizedWords.toLowerCase();
            if (words.contains(kWakePhrase)) _onWakeDetected();
          }
        },
        listenFor: Duration(minutes: 10),
        pauseFor: Duration(seconds: 8),
        partialResults: true,
        listenMode: stt.ListenMode.deviceDefault,
        cancelOnError: false,
      );
    } catch (_) {
      Future.delayed(Duration(seconds: 2), () {
        if (mounted && _isAlwaysOn && !_isConvoMode) _startWakeListening();
      });
    }
  }

  void _onWakeDetected() {
    speech.stop();
    setState(() {
      _isWakeDetected = true;
      _isConvoMode    = true;
      _statusText     = 'LISTENING...';
    });
    _playWakeSound();
    speak("What's up?");
  }

  // ── COMMAND LISTENING ────────────────────────────────────────────────────
  void _listenForCommand() {
    if (!mounted || !_isConvoMode || speech.isListening) return;
    try {
      speech.listen(
        onResult: (result) async {
          if (result.finalResult) {
            final words = result.recognizedWords.toLowerCase().trim();
            if (words.isEmpty) { _listenForCommand(); return; }
            if (words.contains('end') || words.contains('goodbye') ||
                words.contains('bye zapia') || words.contains("that's all")) {
              _endConvo();
              speak('Standing by. Say my name when you need me.');
              return;
            }
            await _processQuery(words);
          }
        },
        listenFor: Duration(minutes: 10),
        pauseFor: Duration(seconds: 10),
        partialResults: true,
        listenMode: stt.ListenMode.deviceDefault,
        cancelOnError: false,
      );
      speech.statusListener = (status) {
        if ((status == stt.SpeechToText.doneStatus ||
            status == stt.SpeechToText.notListeningStatus) &&
            _isConvoMode && !isSpeaking) {
          Future.delayed(Duration(milliseconds: 300), () {
            if (mounted && _isConvoMode && !isSpeaking && !speech.isListening) {
              _listenForCommand();
            }
          });
        }
      };
    } catch (_) {
      Future.delayed(Duration(seconds: 1), () {
        if (mounted && _isConvoMode) _listenForCommand();
      });
    }
  }

  void _endConvo() {
    setState(() {
      _isConvoMode    = false;
      _isWakeDetected = false;
      _statusText     = "SAY  'HEY ZAPIA'  TO START";
    });
    if (_isAlwaysOn) _startAlwaysOn();
  }

  // ── TEXT INPUT BOTTOM SHEET ───────────────────────────────────────────────
  void _openKeyboard() {
    if (speech.isListening) speech.stop();
    _textCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFF0D0D0D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top:   BorderSide(color: kGold.withOpacity(0.6), width: 1.5),
                left:  BorderSide(color: kGold.withOpacity(0.3), width: 1),
                right: BorderSide(color: kGold.withOpacity(0.3), width: 1),
              ),
              boxShadow: [
                BoxShadow(color: kGold.withOpacity(0.15), blurRadius: 30, spreadRadius: 5),
              ],
            ),
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: kGold.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'TYPE YOUR COMMAND',
                  style: TextStyle(
                    color: kGold.withOpacity(0.7),
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      focusNode: _textFocus,
                      autofocus: true,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      cursorColor: kGold,
                      decoration: InputDecoration(
                        hintText: 'Ask ZapiaPrime anything...',
                        hintStyle: TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kPurple.withOpacity(0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kGold, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kPurple.withOpacity(0.4)),
                        ),
                      ),
                      onSubmitted: (val) {
                        Navigator.pop(ctx);
                        _submitTextInput(val);
                      },
                    ),
                  ),
                  SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      final val = _textCtrl.text.trim();
                      Navigator.pop(ctx);
                      _submitTextInput(val);
                    },
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [kGold, kAmber],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: kGold.withOpacity(0.5), blurRadius: 12, spreadRadius: 2),
                        ],
                      ),
                      child: Icon(Icons.send_rounded, color: Colors.black, size: 22),
                    ),
                  ),
                ]),
                SizedBox(height: 8),
                Text('Press Enter or tap ⬆ to send',
                    style: TextStyle(color: Colors.white24, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );

    Future.delayed(Duration(milliseconds: 100), () => _textFocus.requestFocus());
  }

  void _submitTextInput(String val) {
    if (val.isEmpty) return;
    setState(() {
      _isConvoMode    = true;
      _isWakeDetected = true;
      _statusText     = 'PROCESSING...';
    });
    _processQuery(val);
  }

  // ── QUERY ────────────────────────────────────────────────────────────────
  Future<void> _processQuery(String query) async {
    setState(() => _statusText = 'PROCESSING...');
    if (query.contains('time')) { _tellTime(); return; }
    if (query.contains('weather')) { _searchWeb('weather today fort myers'); return; }
    if (query.contains('open ')) { _openApp(query); return; }
    if (query.contains('war chest') || query.contains('warchest')) {
      speak('War chest status: Nexus target three thousand dollars. Citadel target five thousand.');
      return;
    }

    try {
      _history.add({'role': 'user', 'content': query});
      final messages = [
        {'role': 'system', 'content': kSystemPrompt},
        ..._history,
      ];
      final res = await http.post(
        Uri.parse('$kOllamaUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'model': kOllamaModel, 'messages': messages, 'stream': false}),
      ).timeout(Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data  = jsonDecode(res.body);
        final reply = data['message']['content'] as String;
        _history.add({'role': 'assistant', 'content': reply});
        if (_history.length > 20) _history.removeRange(0, 2);
        setState(() => _lastResponse = reply);
        speak(reply);
      } else {
        speak('Ollama returned an error. Check local server.');
      }
    } catch (_) {
      speak('Cannot reach Ollama. Make sure the server is running on port 11434.');
    }
  }

  void _tellTime() {
    final t = DateFormat.jm().format(DateTime.now());
    speak('It is $t, Forgemaster.');
  }

  void _searchWeb(String q) async {
    final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(q)}');
    try { await launchUrl(url, mode: LaunchMode.externalApplication); }
    catch (_) { speak('Could not open browser.'); }
  }

  void _openApp(String query) async {
    final clean = query.replaceAll('open', '').trim();

    // Map: keyword → {package, component}
    final Map<String, Map<String, String>> apps = {
      'youtube':  {'pkg': 'com.google.android.youtube',       'comp': 'com.google.android.youtube.HomeActivity'},
      'chrome':   {'pkg': 'com.android.chrome',               'comp': 'com.google.android.apps.chrome.Main'},
      'whatsapp': {'pkg': 'com.whatsapp',                     'comp': 'com.whatsapp.Main'},
      'maps':     {'pkg': 'com.google.android.apps.maps',     'comp': 'com.google.android.maps.MapsActivity'},
      'gmail':    {'pkg': 'com.google.android.gm',            'comp': 'com.google.android.gm.ConversationListActivityGmail'},
      'settings': {'pkg': 'com.android.settings',             'comp': 'com.android.settings.Settings'},
      'termux':   {'pkg': 'com.termux',                       'comp': 'com.termux.app.TermuxActivity'},
      'camera':   {'pkg': 'com.android.camera2',              'comp': 'com.android.camera.CameraLauncher'},
      'spotify':  {'pkg': 'com.spotify.music',                'comp': 'com.spotify.music.MainActivity'},
      'telegram': {'pkg': 'org.telegram.messenger',           'comp': 'org.telegram.messenger.DefaultIcon'},
      'instagram':{'pkg': 'com.instagram.android',            'comp': 'com.instagram.android.activity.MainTabActivity'},
      'twitter':  {'pkg': 'com.twitter.android',              'comp': 'com.twitter.android.StartActivity'},
      'tiktok':   {'pkg': 'com.zhiliaoapp.musically',         'comp': 'com.ss.android.ugc.aweme.main.MainActivity'},
      'netflix':  {'pkg': 'com.netflix.mediaclient',          'comp': 'com.netflix.mediaclient.ui.launch.UIWebViewActivity'},
      'calculator':{'pkg':'com.android.calculator2',          'comp': 'com.android.calculator2.Calculator'},
      'clock':    {'pkg': 'com.android.deskclock',            'comp': 'com.android.deskclock.DeskClock'},
      'files':    {'pkg': 'com.google.android.apps.nbu.files','comp': 'com.google.android.apps.nbu.files.home.HomeActivity'},
      'phone':    {'pkg': 'com.android.dialer',               'comp': 'com.android.dialer.main.impl.MainActivity'},
      'contacts': {'pkg': 'com.android.contacts',             'comp': 'com.android.contacts.activities.PeopleActivity'},
      'messages': {'pkg': 'com.google.android.apps.messaging','comp': 'com.google.android.apps.messaging.ui.ConversationListActivity'},
    };

    Map<String, String>? app;
    String matchedKey = '';
    for (final e in apps.entries) {
      if (clean.contains(e.key)) { app = e.value; matchedKey = e.key; break; }
    }

    if (app != null) {
      // First try: direct URL scheme (cleanest — no chooser)
      try {
        final Uri? deepLink = _getDeepLink(matchedKey);
        if (deepLink != null) {
          await launchUrl(deepLink, mode: LaunchMode.externalApplication);
          speak('Opening $matchedKey.');
          return;
        }
      } catch (_) {}

      // Fallback: explicit component intent
      try {
        await AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: app['pkg']!,
          componentName: app['comp']!,
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        speak('Opening $matchedKey.');
      } catch (_) {
        speak('Could not open $matchedKey.');
      }
    } else {
      speak('I do not have $clean mapped yet.');
    }
  }

  Uri? _getDeepLink(String key) {
    switch (key) {
      case 'youtube':   return Uri.parse('vnd.youtube://');
      case 'whatsapp':  return Uri.parse('whatsapp://');
      case 'spotify':   return Uri.parse('spotify:');
      case 'instagram': return Uri.parse('instagram://');
      case 'twitter':   return Uri.parse('twitter://');
      case 'telegram':  return Uri.parse('tg://');
      case 'netflix':   return Uri.parse('nflx://');
      default: return null;
    }
  }

  void speak(String text) async {
    if (text.isEmpty) return;
    if (speech.isListening) speech.stop();
    setState(() {
      isSpeaking  = true;
      _statusText = 'ZAPIA SPEAKING...';
    });
    await flutterTts.speak(text.replaceAll(RegExp(r'\*'), ''));
  }

  Future<void> _playWakeSound() async {
    try { await _audioPlayer.play(AssetSource('sounds/wake.mp3')); } catch (_) {}
  }

  Color get _activeColor => _colorAnim.value ?? kGold;

  @override
  void dispose() {
    _animCtrl.dispose();
    _colorCtrl.dispose();
    _wakeTimer?.cancel();
    _bgAnimTimer?.cancel();
    speech.stop();
    _audioPlayer.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // ─── KEYBOARD FAB ────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: _openKeyboard,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [kDeepPurple, kPurple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: kGold.withOpacity(0.7), width: 1.5),
            boxShadow: [
              BoxShadow(color: kGold.withOpacity(0.35),   blurRadius: 16, spreadRadius: 2),
              BoxShadow(color: kPurple.withOpacity(0.4),  blurRadius: 24, spreadRadius: 4),
            ],
          ),
          child: Icon(Icons.keyboard_rounded, color: kGold, size: 26),
        ),
        tooltip: 'Type a command',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (b) =>
              LinearGradient(colors: [kGold, kPurple]).createShader(b),
          child: Text(kAppTitle,
              style: TextStyle(
                  color: Colors.white, fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.bold)),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isAlwaysOn ? Icons.mic : Icons.mic_off,
              color: _isAlwaysOn ? (_isConvoMode ? kPurple : kGold) : Colors.red,
              size: 26,
            ),
            onPressed: () {
              if (_isConvoMode) { _endConvo(); speak('Conversation ended.'); return; }
              if (_isAlwaysOn) {
                speech.stop();
                setState(() { _isAlwaysOn = false; _statusText = 'ALWAYS-ON OFF'; });
              } else {
                _startAlwaysOn();
                speak('Always-on activated.');
              }
            },
          ),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: PantheonGridPainter(
              animated: !_isWakeDetected && !isSpeaking && !_isConvoMode,
            ),
            key: ValueKey(_bgCounter),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
                radius: 1.4,
              ),
            ),
          ),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_isAlwaysOn)
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _isConvoMode ? kPurple : kGold,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: _isConvoMode ? kPurple : kGold,
                          blurRadius: 8, spreadRadius: 2)
                    ],
                  ),
                ),
              if (_isAlwaysOn) SizedBox(width: 8),
              Text(_statusText,
                  style: TextStyle(
                      color: _isConvoMode
                          ? kPurple
                          : _isWakeDetected ? kGold : Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
            ]),
          ),
          SizedBox(height: 30),
          AnimatedBuilder(
            animation: Listenable.merge([_pulseAnim, _colorAnim]),
            builder: (context, _) {
              final c = _activeColor;
              return GestureDetector(
                onTap: () {
                  if (_isConvoMode) {
                    _endConvo();
                    speak('Standing by.');
                  } else {
                    _onWakeDetected();
                  }
                },
                child: Transform.scale(
                  scale: (_isWakeDetected || isSpeaking || _isConvoMode)
                      ? _pulseAnim.value
                      : 1.0,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [c.withOpacity(0.85), c.withOpacity(0.5), Colors.transparent],
                        radius: 0.9,
                      ),
                      boxShadow: [
                        BoxShadow(color: c.withOpacity(0.6),        blurRadius: 40, spreadRadius: 10),
                        BoxShadow(color: kPurple.withOpacity(0.3),  blurRadius: 70, spreadRadius: 20),
                      ],
                      border: Border.all(color: c.withOpacity(0.6), width: 2),
                    ),
                    child: Stack(alignment: Alignment.center, children: [
                      CustomPaint(painter: TrianglePainter(color: c),
                          child: SizedBox(width: 200, height: 200)),
                      Text('Z',
                          style: TextStyle(
                              color: c,
                              fontSize: 64,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: c, blurRadius: 20)])),
                    ]),
                  ),
                ),
              );
            },
          ),
          SizedBox(height: 40),
          if (_lastResponse.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _lastResponse.length > 120
                    ? _lastResponse.substring(0, 120) + '...'
                    : _lastResponse,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
              ),
            ),
          SizedBox(height: 20),
          Text('TAP ORB  •  SAY "HEY ZAPIA"  •  OR ⌨️ TYPE',
              style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2)),
        ]),
      ]),
    );
  }
}

// ─── PAINTERS ─────────────────────────────────────────────────────────────────
class PantheonGridPainter extends CustomPainter {
  final bool animated;
  PantheonGridPainter({this.animated = true});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(animated ? DateTime.now().millisecondsSinceEpoch ~/ 8000 : 42);
    final linePaint = Paint()
      ..color = kGold.withOpacity(0.08)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = kPurple.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final nodes = List.generate(
        20, (_) => Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height));
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        if (rng.nextDouble() < 0.3) canvas.drawLine(nodes[i], nodes[j], linePaint);
      }
    }
    for (final n in nodes) canvas.drawCircle(n, 3, dotPaint);
  }

  @override
  bool shouldRepaint(_) => true;
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = size.width * 0.38;
    final paint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path();
    path.moveTo(cx + r * cos(-pi / 2), cy + r * sin(-pi / 2));
    path.lineTo(cx + r * cos(-pi / 2 + 2 * pi / 3), cy + r * sin(-pi / 2 + 2 * pi / 3));
    path.lineTo(cx + r * cos(-pi / 2 + 4 * pi / 3), cy + r * sin(-pi / 2 + 4 * pi / 3));
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
