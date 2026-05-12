part of '../sensors_screen.dart';

class _DarkDialog extends StatelessWidget {
  const _DarkDialog({
    required this.title,
    required this.content,
    required this.actions,
  });
  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    final sch = AppColors.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Container(
        constraints: BoxConstraints(maxHeight: screenH * 0.88),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sch.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Заголовок ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: sch.textMain,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  // Кнопка ✕ закрытия в шапке
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: sch.card2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.close, color: sch.textDim, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: sch.border),

            // ── Контент (скроллируемый) ───────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: content,
              ),
            ),

            // ── Кнопки действий ───────────────────────────────────────────
            if (actions.isNotEmpty) ...[
              Divider(height: 1, color: sch.border),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.readOnly = false,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: TextStyle(
        color: readOnly ? sch.textDim : sch.textMain,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: sch.textDim, fontSize: 13),
        hintStyle: TextStyle(color: sch.textDim, fontSize: 12),
        filled: readOnly,
        fillColor: readOnly ? sch.card2 : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: readOnly ? sch.border.withOpacity(0.5) : sch.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: readOnly ? sch.border.withOpacity(0.5) : kCyan,
          ),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
  }
}

class _DarkDropdown<T> extends StatelessWidget {
  const _DarkDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: TextStyle(color: sch.textMain, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: sch.textDim, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: sch.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCyan),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _DarkTextButton extends StatelessWidget {
  const _DarkTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sch = AppColors.of(context);
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: TextStyle(color: sch.textDim, fontSize: 13)),
    );
  }
}

class _DarkFilledButton extends StatelessWidget {
  const _DarkFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: kCyan,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

// ── Расширение для mapIndexed ─────────────────────────────────────────────────

extension _IndexedIterable<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) f) {
    var i = 0;
    return map((e) => f(i++, e));
  }
}
