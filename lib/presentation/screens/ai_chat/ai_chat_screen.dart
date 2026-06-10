import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});
  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg>  _messages = [];
  bool _sending = false;

  // Voice input
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  final _suggestions = const [
    'How much water should I drink today? 💧',
    'What are signs of dehydration?',
    'Best time to hydrate during workouts?',
    'Does coffee count toward hydration?',
    'How does sleep affect hydration?',
    'Tips for drinking more water daily',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(const _Msg(
        role: 'assistant',
        text: 'Hello! I\'m your HydroIQ AI coach 💧\n'
            'Ask me anything — hydration, health, fitness, or general questions!'));
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) { if (mounted) setState(() => _isListening = false); },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoice() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        _msgCtrl.text = result.recognizedWords;
        _msgCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _msgCtrl.text.length));
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          setState(() => _isListening = false);
          _send(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      localeId: 'en_US',
    );
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    _msgCtrl.clear();

    setState(() {
      _messages.add(_Msg(role: 'user', text: trimmed));
      _sending = true;
    });
    _scrollToBottom();

    final history = _messages
        .where((m) => !(_messages.indexOf(m) == 0))
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();

    final aiService = ref.read(aiServiceProvider);
    String reply;
    try {
      reply = await aiService.sendMessage(trimmed, history);
    } catch (e) {
      reply = '💧 I\'m here to help! Ask me about hydration, health, fitness, or anything else!';
    }

    if (mounted) {
      setState(() {
        _messages.add(_Msg(role: 'assistant', text: reply));
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clear() {
    setState(() {
      _messages.clear();
      _messages.add(const _Msg(
          role: 'assistant',
          text: 'Chat cleared! Ask me anything 💧'));
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showWelcome = _messages.length == 1 && !_sending;

    return Scaffold(
      body: Column(children: [
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
                borderRadius: BorderRadius.circular(14)),
              child: const Text('🧠', style: TextStyle(fontSize: 22))),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('HydroIQ AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('Your smart assistant', style: TextStyle(fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Clear chat', onPressed: _clear),
          ]),
        )),

        Expanded(
          child: showWelcome
              ? _WelcomeView(suggestions: _suggestions, onTap: _send)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _messages.length) return const _TypingIndicator();
                    return _Bubble(msg: _messages[i]);
                  }),
        ),

        if (!showWelcome && !_sending)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _suggestions.take(4).map((s) => GestureDetector(
                onTap: () => _send(s),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2))),
                  child: Text(s.length > 28 ? '${s.substring(0, 28)}…' : s,
                      style: const TextStyle(fontSize: 12))),
              )).toList(),
            ),
          ),

        // Input bar with mic button
        Container(
          padding: EdgeInsets.fromLTRB(
              16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 16, offset: const Offset(0, -4))]),
          child: Row(children: [
            // Mic button
            if (_speechAvailable)
              GestureDetector(
                onTap: _toggleVoice,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _isListening
                        ? Colors.redAccent.withOpacity(0.15)
                        : AppTheme.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent
                          : AppTheme.primaryBlue.withOpacity(0.3))),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.redAccent : AppTheme.primaryBlue,
                    size: 20),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: _sending ? null : _send,
                decoration: InputDecoration(
                  hintText: _isListening ? '🎤 Listening…' : 'Ask anything…',
                  filled: true,
                  fillColor: isDark ? AppTheme.darkCardAlt : const Color(0xFFF0F4FF),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : () => _send(_msgCtrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _sending
                        ? [Colors.grey.shade400, Colors.grey.shade500]
                        : [const Color(0xFF0D47A1), const Color(0xFF29B6F6)]),
                  borderRadius: BorderRadius.circular(16)),
                child: _sending
                    ? const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : const Icon(Icons.send, color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Msg {
  final String role, text;
  const _Msg({required this.role, required this.text});
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble({super.key, required this.msg});
  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
                borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('🧠', style: TextStyle(fontSize: 16)))),
            const SizedBox(width: 8),
          ],
          Flexible(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: isUser ? const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF29B6F6)]) : null,
              color: isUser ? null : (isDark ? AppTheme.darkCard : const Color(0xFFF0F4FF)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0,2))]),
            child: Text(msg.text,
                style: TextStyle(color: isUser ? Colors.white : null, fontSize: 14, height: 1.55)),
          )),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
            borderRadius: BorderRadius.circular(10)),
          child: const Center(child: Text('🧠', style: TextStyle(fontSize: 16)))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : const Color(0xFFF0F4FF),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18), topRight: Radius.circular(18),
              bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(delay: 0), SizedBox(width: 5),
            _Dot(delay: 180), SizedBox(width: 5),
            _Dot(delay: 360),
          ])),
      ]),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}
class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(width: 8, height: 8,
        decoration: const BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle)));
}

class _WelcomeView extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onTap;
  const _WelcomeView({required this.suggestions, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF29B6F6).withOpacity(0.35), blurRadius: 20, spreadRadius: 2)]),
          child: const Text('🧠', style: TextStyle(fontSize: 48))),
        const SizedBox(height: 20),
        const Text('HydroIQ AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Ask anything — hydration, health, fitness, or general questions.\nTap mic 🎤 to speak.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13,
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54)),
        const SizedBox(height: 32),
        Align(alignment: Alignment.centerLeft,
          child: Text('Suggested questions',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black45))),
        const SizedBox(height: 12),
        ...suggestions.map((s) => GestureDetector(
          onTap: () => onTap(s),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18))),
            child: Row(children: [
              const Text('💬', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 14))),
              Icon(Icons.arrow_forward_ios, size: 13, color: AppTheme.primaryBlue.withOpacity(0.5)),
            ]),
          ),
        )),
      ]),
    );
  }
}
