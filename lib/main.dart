import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _nvidiaEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
const _defaultModel = 'qwen/qwen3-coder-480b-a35b-instruct';

void main() => runApp(const AiAgentApp());

class AiAgentApp extends StatelessWidget {
  const AiAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Agent',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true, brightness: Brightness.dark),
      home: const AgentHomePage(),
    );
  }
}

class ChatMessage {
  ChatMessage(this.role, this.content);
  final String role;
  final String content;
}

class NvidiaClient {
  Future<String> complete({required String apiKey, required List<ChatMessage> messages, String model = _defaultModel}) async {
    final response = await http.post(
      Uri.parse(_nvidiaEndpoint),
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': 'You are an expert Android coding agent. Give concrete, safe, production-ready code. When given project context, inspect it carefully before suggesting changes.'},
          ...messages.map((m) => {'role': m.role, 'content': m.content}),
        ],
        'temperature': 0.2,
        'max_tokens': 2048,
        'stream': false,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('NVIDIA API ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['choices'] as List).first['message']['content'] ?? '').toString();
  }
}

class AgentHomePage extends StatefulWidget {
  const AgentHomePage({super.key});
  @override
  State<AgentHomePage> createState() => _AgentHomePageState();
}

class _AgentHomePageState extends State<AgentHomePage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _client = NvidiaClient();
  final List<ChatMessage> _messages = [];
  final List<String> _files = [];
  String _apiKey = '';
  bool _busy = false;
  String _model = _defaultModel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('nvidia_api_key') ?? '';
      _model = prefs.getString('nvidia_model') ?? _defaultModel;
    });
  }

  Future<void> _saveSettings(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nvidia_api_key', key.trim());
    await prefs.setString('nvidia_model', model.trim());
    setState(() { _apiKey = key.trim(); _model = model.trim().isEmpty ? _defaultModel : model.trim(); });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null) return;
    setState(() {
      _files
        ..clear()
        ..addAll(result.files.map((f) => f.name));
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (_apiKey.isEmpty) {
      await _showSettings();
      if (_apiKey.isEmpty) return;
    }
    final contextText = _files.isEmpty ? '' : '\n\nProject files selected: ${_files.join(', ')}';
    _input.clear();
    setState(() {
      _messages.add(ChatMessage('user', '$text$contextText'));
      _busy = true;
    });
    try {
      final answer = await _client.complete(apiKey: _apiKey, messages: _messages, model: _model);
      setState(() => _messages.add(ChatMessage('assistant', answer)));
    } catch (e) {
      setState(() => _messages.add(ChatMessage('assistant', 'Error: $e')));
    } finally {
      setState(() => _busy = false);
      if (_scroll.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    }
  }

  Future<void> _showSettings() async {
    final key = TextEditingController(text: _apiKey);
    final model = TextEditingController(text: _model);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('NVIDIA API settings'), subtitle: Text('Your key is stored locally on this device.')),
          TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'NVIDIA API key', prefixIcon: Icon(Icons.key))),
          const SizedBox(height: 12),
          TextField(controller: model, decoration: const InputDecoration(labelText: 'Model')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () async { await _saveSettings(key.text, model.text); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.save), label: const Text('Save')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.auto_awesome), SizedBox(width: 10), Text('AI Agent')]),
        actions: [IconButton(onPressed: _showSettings, icon: const Icon(Icons.settings)), const SizedBox(width: 8)],
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.code_rounded, size: 72), const SizedBox(height: 18),
                  Text('Your Android coding agent', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  const Text('Ask for code, debugging, architecture, refactors, or a complete implementation.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: ['Build a login screen', 'Fix this crash', 'Create a REST client'].map((s) => ActionChip(label: Text(s), onPressed: () { _input.text = s; })).toList()),
                ])))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length + (_busy ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_busy && index == _messages.length) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
                    final message = _messages[index];
                    final isUser = message.role == 'user';
                    return Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
                      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                      child: isUser ? Text(message.content) : MarkdownBody(data: message.content),
                    ));
                  },
                ),
        ),
        if (_files.isNotEmpty) SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: _files.map((f) => Padding(padding: const EdgeInsets.only(right: 6), child: InputChip(avatar: const Icon(Icons.description, size: 16), label: Text(f), onDeleted: () => setState(() => _files.remove(f))))).toList())),
        SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          IconButton(onPressed: _pickFiles, icon: const Icon(Icons.attach_file)),
          Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 6, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Ask your coding agent...', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          FloatingActionButton.small(onPressed: _send, child: const Icon(Icons.arrow_upward)),
        ]))),
      ]),
    );
  }
}
