import 'package:material_ui/material_ui.dart';

class FolderNameDialog extends StatefulWidget {
  const FolderNameDialog({super.key, required this.folders, this.existing});
  final List<String> folders;
  final String? existing;

  @override
  State<FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<FolderNameDialog> {
  late final _name = TextEditingController(text: widget.existing);
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final value = _name.text.trim();
    final duplicate = widget.folders.any(
      (name) =>
          name.toLowerCase() == value.toLowerCase() && name != widget.existing,
    );
    if (value.isEmpty ||
        value.length > 60 ||
        value.contains(RegExp(r'[\x00-\x1f/\\]'))) {
      setState(() => _error = 'Use 1–60 characters.');
    } else if (duplicate ||
        const {'unfiled', 'all downloads'}.contains(value.toLowerCase())) {
      setState(() => _error = 'That folder name is already in use.');
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New folder' : 'Rename folder'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 60,
      decoration: InputDecoration(labelText: 'Folder name', errorText: _error),
      textCapitalization: TextCapitalization.sentences,
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
