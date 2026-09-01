import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/category_dropdown.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key, required this.groupId});
  final String groupId;
  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  String? _categoryId;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _private = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Pick a sport');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Pick a date');
      return;
    }
    // The venue pins the event to its own timezone — required.
    if (_location.text.trim().isEmpty) {
      setState(() => _error =
          'Add the venue (street/park and city) so players can find it.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(manageRepositoryProvider).createEvent({
        'title': _title.text.trim(),
        'categoryId': _categoryId,
        'groupId': widget.groupId,
        'eventDate': DateTime.utc(_date!.year, _date!.month, _date!.day)
            .toIso8601String(),
        'locationName': _location.text.trim().isEmpty ? null : _location.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'startTime': _start != null ? _hhmm(_start!) : null,
        'endTime': _end != null ? _hhmm(_end!) : null,
        'visibility': _private ? 'private' : 'public',
      });
      ref.invalidate(groupEventsProvider(widget.groupId));
      ref.invalidate(discoverProvider);
      final slug = res['slug'];
      if (!mounted) return;
      if (slug is String && slug.isNotEmpty) {
        context.pushReplacement('/events/$slug');
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
      appBar: AppBar(title: const Text('New event')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a title' : null,
            ),
            const SizedBox(height: 14),
            CategoryDropdown(value: _categoryId, onChanged: (v) => setState(() => _categoryId = v)),
            const SizedBox(height: 14),
            _PickerTile(
              label: 'Date',
              value: _date == null ? 'Choose' : DateFormat('EEE, d MMM yyyy').format(_date!),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? now,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 3),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            Row(children: [
              Expanded(
                child: _PickerTile(
                  label: 'Start',
                  value: _start == null ? 'Optional' : _start!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _start ?? TimeOfDay.now());
                    if (t != null) setState(() => _start = t);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerTile(
                  label: 'End',
                  value: _end == null ? 'Optional' : _end!.format(context),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: _end ?? TimeOfDay.now());
                    if (t != null) setState(() => _end = t);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location (optional)'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Private event'),
              subtitle: Text('Only your group can see it',
                  style: TextStyle(color: p.muted, fontSize: 12)),
              value: _private,
              onChanged: (v) => setState(() => _private = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create event'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(value, style: TextStyle(color: p.ink)),
        ),
      ),
    );
  }
}
