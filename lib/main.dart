import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CloudQuizApp());
}

class CloudQuizApp extends StatelessWidget {
  const CloudQuizApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cloud Quiz · Class A', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) => snapshot.data == null ? const LoginPage() : QuizPage(user: snapshot.data!),
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;
  Future<void> login() async {
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = 'Sign-in error: ${e.code}');
    } catch (e) {
      if (mounted) setState(() => error = 'Sign-in unavailable: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud Quiz · Sign in')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_done_outlined, size: 64),
        const SizedBox(height: 16), const Text('Class A · General Knowledge', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 20), FilledButton(onPressed: busy ? null : login, child: Text(busy ? 'Signing in…' : 'Sign in')),
      ]),
    ))),
  );
}

class QuizQuestion {
  QuizQuestion(this.prompt, this.correct, this.choices);
  final String prompt, correct;
  final List<String> choices;
  static QuizQuestion parse(dynamic value) {
    if (value is! Map<String, dynamic>) throw const FormatException('Invalid question object');
    if (value['category'] != 'General Knowledge' || value['difficulty'] != 'easy' || value['type'] != 'multiple') {
      throw const FormatException('Wrong category, difficulty, or type');
    }
    final decode = HtmlUnescape().convert;
    if (value['question'] is! String || value['correct_answer'] is! String || value['incorrect_answers'] is! List) {
      throw const FormatException('Missing question fields');
    }
    final wrong = value['incorrect_answers'] as List;
    if (wrong.length != 3 || wrong.any((v) => v is! String)) throw const FormatException('Expected three wrong answers');
    final prompt = decode(value['question'] as String).trim();
    final correct = decode(value['correct_answer'] as String).trim();
    final options = <String>[correct, ...wrong.map((v) => decode(v as String).trim())];
    if (prompt.isEmpty || options.any((v) => v.isEmpty) || options.toSet().length != 4) {
      throw const FormatException('Empty or duplicate decoded choices');
    }
    options.shuffle(Random.secure());
    return QuizQuestion(prompt, correct, options);
  }
}

enum SavePhase { ready, submitting, verifying, saveUnknown, verificationUnavailable, permissionDenied, cloudVerified, collision }

class AttemptRepository {
  AttemptRepository(this.uid, this.roundId);
  final String uid, roundId;
  DocumentReference<Map<String, dynamic>> get ref => FirebaseFirestore.instance.doc('users/$uid/attempts/$roundId');
  Map<String, dynamic> payload(int correct) => {
    'schemaVersion': 1, 'variant': 'A', 'categoryId': 9,
    'questionCount': 10, 'correctCount': correct,
    'submittedAt': FieldValue.serverTimestamp(),
  };
  bool matches(Map<String, dynamic>? data, int correct) => data != null &&
    data.length == 6 && data['schemaVersion'] == 1 && data['variant'] == 'A' &&
    data['categoryId'] == 9 && data['questionCount'] == 10 && data['correctCount'] == correct;
  Future<void> createOnce(int correct) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        if (!matches(snapshot.data(), correct)) throw const AttemptCollision();
      } else {
        transaction.set(ref, payload(correct));
      }
    });
  }
  Future<bool> verify(int correct) async {
    final snapshot = await ref.get(const GetOptions(source: Source.server));
    return snapshot.exists && !snapshot.metadata.hasPendingWrites &&
      matches(snapshot.data(), correct) && snapshot.data()?['submittedAt'] is Timestamp;
  }
}
class AttemptCollision implements Exception { const AttemptCollision(); }

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.user});
  final User user;
  @override State<QuizPage> createState() => _QuizPageState();
}
class _QuizPageState extends State<QuizPage> {
  static final url = Uri.parse('https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple');
  List<QuizQuestion> questions = [];
  List<String?> selected = List.filled(10, null);
  int index = 0;
  String? error, status;
  bool loading = false, finished = false;
  SavePhase phase = SavePhase.ready;
  String? roundId;
  DateTime? lastFetch;
  bool injectLostAcknowledgement = false;
  bool injectUnavailable = false;
  bool injectExhausted = false;
  String? savedRoundId;
  int get score => List.generate(questions.length, (i) => selected[i] == questions[i].correct ? 1 : 0).fold(0, (a,b) => a+b);
  bool get unresolved => phase == SavePhase.submitting || phase == SavePhase.verifying || phase == SavePhase.saveUnknown || phase == SavePhase.verificationUnavailable;
  AttemptRepository get repo => AttemptRepository(widget.user.uid, roundId!);
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (unresolved) return;
    final elapsed = lastFetch == null ? const Duration(seconds: 5) : DateTime.now().difference(lastFetch!);
    if (elapsed < const Duration(seconds: 5)) {
      setState(() => error = 'Please wait ${5 - elapsed.inSeconds} seconds before requesting another round.');
      return;
    }
    setState(() { loading = true; error = null; status = null; finished = false; questions = []; index = 0; selected = List.filled(10, null); phase = SavePhase.ready; savedRoundId = null; });
    lastFetch = DateTime.now();
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw FormatException('HTTP ${response.statusCode}');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['response_code'] != 0 || decoded['results'] is! List) {
        throw const FormatException('Trivia API did not return success');
      }
      final results = decoded['results'] as List;
      if (results.length != 10) throw const FormatException('Expected exactly 10 questions');
      final parsed = results.map(QuizQuestion.parse).toList();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.user.uid) return;
      setState(() { questions = parsed; roundId = FirebaseFirestore.instance.collection('users/${widget.user.uid}/attempts').doc().id; });
    } catch (e) { if (mounted) setState(() => error = 'Could not load valid questions: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  void answer(String value) {
    if (selected[index] != null || finished) return;
    setState(() => selected[index] = value);
  }
  void next() {
    if (selected[index] == null) return;
    setState(() { if (index == 9) { finished = true; } else { index++; } });
  }
  Future<void> reconcile() async {
    if (roundId == null) return;
    final uid = widget.user.uid, id = roundId!;
    setState(() { phase = SavePhase.verifying; status = 'Checking the original attempt directly on the server…'; });
    try {
      final ok = await repo.verify(score);
      if (!mounted || widget.user.uid != uid || FirebaseAuth.instance.currentUser?.uid != uid || roundId != id) return;
      if (ok) { setState(() { phase = SavePhase.cloudVerified; savedRoundId = id; status = 'Cloud verified · users/$uid/attempts/$id'; }); }
      else { setState(() { phase = SavePhase.saveUnknown; status = 'No matching server document confirmed. Reconcile or retry with the SAME ID.'; }); }
    } on FirebaseException catch (e) {
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid || roundId != id) return;
      setState(() { phase = e.code == 'permission-denied' ? SavePhase.permissionDenied : SavePhase.verificationUnavailable; status = 'Server verification unavailable (${e.code}). Save status is unknown.'; });
    } catch (e) { if (mounted) setState(() { phase = SavePhase.verificationUnavailable; status = 'Verification unavailable: $e'; }); }
  }
  Future<void> submit() async {
    if (!finished || phase == SavePhase.submitting || phase == SavePhase.verifying || phase == SavePhase.cloudVerified || roundId == null) return;
    final uid = widget.user.uid, id = roundId!;
    setState(() { phase = SavePhase.submitting; status = 'Creating or reconciling immutable attempt…'; });
    try {
      if (injectUnavailable) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      if (injectExhausted) throw FirebaseException(plugin: 'cloud_firestore', code: 'resource-exhausted');
      await repo.createOnce(score).timeout(const Duration(seconds: 10));
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid || roundId != id) return;
      if (injectLostAcknowledgement) {
        setState(() { phase = SavePhase.saveUnknown; status = 'INJECTED: acknowledgement hidden after real commit. Reconcile with server read.'; });
        return;
      }
      await reconcile();
    } on AttemptCollision {
      if (mounted) setState(() { phase = SavePhase.collision; status = 'Collision: this ID already contains a different payload. Original preserved.'; });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() { phase = e.code == 'permission-denied' ? SavePhase.permissionDenied : SavePhase.saveUnknown; status = '${injectUnavailable || injectExhausted ? 'INJECTED ' : ''}${e.code}: no cloud success claimed. Reconcile before retry.'; });
    } on TimeoutException {
      if (mounted) setState(() { phase = SavePhase.saveUnknown; status = 'Acknowledgement timed out. Write may have committed; reconcile same ID.'; });
    } catch (e) {
      if (mounted) setState(() { phase = SavePhase.saveUnknown; status = 'Save outcome unknown: $e'; });
    }
  }
  Future<void> restore() async {
    if (savedRoundId == null) return;
    await reconcile();
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cloud Quiz · Class A'), actions: [
      IconButton(tooltip: 'Sign out', onPressed: unresolved ? null : () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
    ]),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Signed in: ${widget.user.email ?? widget.user.uid}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      if (loading) const Center(child: CircularProgressIndicator()),
      if (error != null) ...[Text(error!, style: const TextStyle(color: Colors.red)), const SizedBox(height: 12), FilledButton(onPressed: loading ? null : load, child: const Text('Retry questions'))],
      if (questions.isNotEmpty && !finished) ...[
        LinearProgressIndicator(value: (index + 1) / 10), const SizedBox(height: 16),
        Text('Question ${index + 1} of 10', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12), Text(questions[index].prompt, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final option in questions[index].choices) Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(
          onPressed: selected[index] == null ? () => answer(option) : null,
          child: Row(children: [Expanded(child: Text(option)), if (selected[index] == option) Icon(option == questions[index].correct ? Icons.check_circle : Icons.cancel, color: option == questions[index].correct ? Colors.green : Colors.red)]),
        )),
        if (selected[index] != null) Text(selected[index] == questions[index].correct ? 'Correct!' : 'Incorrect. Correct: ${questions[index].correct}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16), FilledButton(onPressed: selected[index] == null ? null : next, child: Text(index == 9 ? 'Review round' : 'Next question')),
      ],
      if (finished) ...[
        Text('Final score: $score / 10', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        for (var i = 0; i < questions.length; i++) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${i + 1}. ${questions[i].prompt}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Your answer: ${selected[i]}'), Text('Correct answer: ${questions[i].correct}'),
        ]))),
        Text('Attempt ID: $roundId', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        FilledButton(onPressed: phase == SavePhase.ready || phase == SavePhase.saveUnknown || phase == SavePhase.verificationUnavailable ? submit : null, child: Text(phase == SavePhase.cloudVerified ? 'Cloud verified' : 'Submit / Retry same ID')),
        if (phase == SavePhase.saveUnknown || phase == SavePhase.verificationUnavailable) OutlinedButton(onPressed: reconcile, child: const Text('Reconcile with server')),
        if (status != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(status!)),
        OutlinedButton(onPressed: unresolved ? null : load, child: const Text('Replay · new attempt ID')),
        const Divider(), const Text('Development-only fault injection', style: TextStyle(fontWeight: FontWeight.bold)),
        SwitchListTile(title: const Text('Hide acknowledgement after real commit'), value: injectLostAcknowledgement, onChanged: unresolved ? null : (v) => setState(() => injectLostAcknowledgement = v)),
        SwitchListTile(title: const Text('Inject unavailable'), value: injectUnavailable, onChanged: unresolved ? null : (v) => setState(() => injectUnavailable = v)),
        SwitchListTile(title: const Text('Inject resource-exhausted'), value: injectExhausted, onChanged: unresolved ? null : (v) => setState(() => injectExhausted = v)),
      ],
    ]))),
  );
}
