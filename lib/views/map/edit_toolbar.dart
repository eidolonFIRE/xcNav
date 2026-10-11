import 'package:flutter/material.dart';

/// Row of buttons shown while adding / editing a waypoint or path.
/// [onEdit] and [onConfirm] are hidden when null.
class EditToolbar extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback onUndo;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;

  const EditToolbar({super.key, required this.onDelete, required this.onUndo, this.onEdit, this.onConfirm});

  Widget _button({required Icon icon, required VoidCallback onPressed}) {
    return CircleAvatar(
      backgroundColor: Colors.white,
      maxRadius: 20,
      child: IconButton(
        iconSize: 40,
        padding: EdgeInsets.zero,
        icon: icon,
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _button(icon: const Icon(Icons.delete, size: 35, color: Colors.red), onPressed: onDelete),
        const SizedBox(
          width: 10,
          height: 1,
        ),
        _button(icon: const Icon(Icons.undo, size: 35, color: Colors.black), onPressed: onUndo),
        if (onEdit != null) _button(icon: const Icon(Icons.edit, size: 30, color: Colors.blue), onPressed: onEdit!),
        if (onConfirm != null)
          _button(icon: const Icon(Icons.check_circle, size: 40, color: Colors.green), onPressed: onConfirm!),
      ],
    );
  }
}
