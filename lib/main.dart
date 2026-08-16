import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _nvidiaEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
const _defaultModel = 'qwen/qwen3-coder-480b-a35b-instruct';
const _maxContextChars = 50000;

void main() => runApp(const AiAgentApp());

class AiAgentApp extends StatelessWidget {
  const AiAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Agent',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const AgentHomePage(),
    );
  }
}

class ChatMessage {
  ChatMessage(this.role, this.content);
  final String role;
  final String content;
}

class ProjectFile {
  ProjectFile(this.name, this.content);
  final String name;
  final String content;
}

class NvidiaClient {
  Future<String> complete({
    required String apiKey,
    required List<ChatMessage> messages,
    String model = _defaultModel,
  }) async {
    final response = await http
        .post(
          Uri.parse(_nvidiaEndpoint),
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'model': model.trim().isEmpty ? _defaultModel : model.trim(),
            'messages': [
              {
                'role': 'system',
                'content': '''You are an expert Android coding agent.
Give concrete, production-ready code and explain important changes briefly.
When project files are supplied, inspect the actual contents before proposing edits.
Prefer complete implementations over pseudocode. Never claim to have changed a file unless the user/app actually performs that change.''',
              },
              ...messages.map((m) => {
                    'role': m.role,
                    'content': m.content,
                  }),
            ],
            'temperature': 0.2,
            'max_tokens': 4096,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 90));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('NVIDIA API returned invalid JSON (${response.statusCode}).');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'];
      final message = error is Map ? error['message'] : null;
      throw Exception(
        'NVIDIA API ${response.statusCode}: ${message ?? response.body}',
      );
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('NVIDIA API returned no choices.');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    if (content == null || content.toString().trim().isEmpty) {
      throw Exception('NVIDIA API returned an empty response.');
    }
    return content.toString();
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
  final List<ProjectFile> _files = [];
  String _apiKey = '';
  bool _busy = false;
  String _model = _defaultModel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _apiKey = prefs.getString('nvidia_api_key') ?? '';
      _model = prefs.getString('nvidia_model') ?? _defaultModel;
    });
  }

  Future<void> _saveSettings(String key, String model) async {
    final normalizedKey = key.trim();
    final normalizedModel = model.trim().isEmpty ? _defaultModel : model.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nvidia_api_key', normalizedKey);
    await prefs.setString('nvidia_model', normalizedModel);
    if (!mounted) return;
    setState(() {
      _apiKey = normalizedKey;
      _model = normalizedModel;
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null) return;

    var remaining = _maxContextChars;
    final selected = <ProjectFile>[];
    for (final file in result.files) {
      if (remaining <= 0) break;
      final bytes = file.bytes;
      if (bytes == null) continue;
      final decoded = utf8.decode(bytes, allowMalformed: true);
      final content = decoded.length > remaining
          ? decoded.substring(0, remaining)
          : decoded;
      selected.add(ProjectFile(file.name, content));
      remaining -= content.length;
    }

    if (!mounted) return;
    setState(() {
      _files
        ..clear()
        ..addAll(selected);
    });

    if (selected.isEmpty) {
      _showSnack('Could not read the selected files.');
    } else if (selected.length < result.files.length) {
      _showSnack('Project context limited to $_maxContextChars characters.');
    }
  }

  String _projectContext() {
    if (_files.isEmpty) return '';
    final buffer = StringBuffer('\n\nPROJECT CONTEXT:\n');
    for (final file in _files) {
      buffer
        ..writeln('\n--- ${file.name} ---')
        ..writeln(file.content);
    }
    return buffer.toString();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (_apiKey.isEmpty) {
      await _showSettings();
      if (_apiKey.isEmpty) return;
    }

    final userContent = '$text${_projectContext()}';
    _input.clear();
    setState(() {
      _messages.add(ChatMessage('user', userContent));
      _busy = true;
    });
    _scrollToBottom();

    try {
      final answer = await _client.complete(
        apiKey: _apiKey,
        messages: _messages,
        model: _model,
      );
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage('assistant', answer)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage('assistant', '⚠️ $e')));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSettings() async {
    final key = TextEditingController(text: _apiKey);
    final model = TextEditingController(text: _model);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('NVIDIA API settings'),
              subtitle: Text('The API key is stored locally on this device.'),
            ),
            TextField(
              controller: key,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'NVIDIA API key',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: model,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Model',
                prefixIcon: Icon(Icons.memory),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await _saveSettings(key.text, model.text);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
    key.dispose();
    model.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome),
            SizedBox(width: 10),
            Text('AI Agent'),
          ],
        ),
        actions: [
          IconButton(onPressed: _showSettings, icon: const Icon(Icons.settings)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.code_rounded, size: 72),
                          const SizedBox(height: 18),
                          Text(
                            'Your Android coding agent',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Ask for code, debugging, architecture, refactors, or a complete implementation.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              'Build a login screen',
                              'Fix this crash',
                              'Create a REST client',
                            ]
                                .map(
                                  (s) => ActionChip(
                                    label: Text(s),
                                    onPressed: () => setState(() => _input.text = s),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_busy && index == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator(),
                        );
                      }
                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.9,
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: isUser
                              ? SelectableText(message.content)
                              : MarkdownBody(data: message.content),
                        ),
                      );
                    },
                  ),
          ),
          if (_files.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _files
                    .map(
                      (file) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          avatar: const Icon(Icons.description, size: 16),
                          label: Text(file.name),
                          onDeleted: () => setState(() => _files.remove(file)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _busy ? null : _pickFiles,
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 6,
                      enabled: !_busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask your coding agent...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: _busy ? null : _send,
                    child: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
