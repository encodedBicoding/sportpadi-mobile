import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/category_dropdown.dart';

class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key, required this.groupId});
  final String groupId;
  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _venue = TextEditingController();
  final _description = TextEditingController();
  String? _categoryId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Pick a sport');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(manageRepositoryProvider).createTeam(widget.groupId, {
        'categoryId': _categoryId,
        'name': _name.text.trim(),
        'homeVenue': _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      });
      ref.invalidate(groupTeamsProvider(widget.groupId));
      final id = res['id'];
      if (!mounted) return;
      if (id is String && id.isNotEmpty) {
        context.pushReplacement('/teams/$id');
      } else {
        context.pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('New team')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Team name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a name' : null,
            ),
            const SizedBox(height: 14),
            CategoryDropdown(value: _categoryId, onChanged: (v) => setState(() => _categoryId = v)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _venue,
              decoration: const InputDecoration(labelText: 'Home venue (optional)'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create team'),
            ),
          ],
        ),
      ),
    );
  }
}
