part of '../reports_screen.dart';

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: child,
    );
  }
}

/// Подзаголовок секции
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).textDim,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Таб-переключатель (датчик / локация)
class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.of(context).cyan.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? AppColors.of(context).cyan.withOpacity(0.6)
                : AppColors.of(context).border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected
                ? AppColors.of(context).cyan
                : AppColors.of(context).textDim,
          ),
        ),
      ),
    );
  }
}

/// Стилизованный дропдаун
class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
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
    final c = AppColors.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: TextStyle(color: c.textMain, fontSize: 13),
      iconEnabledColor: c.textDim,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textDim, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: c.cyan),
        ),
        filled: true,
        fillColor: c.card2,
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

/// Кнопка выбора даты
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.onTap,
    required this.active,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.of(context).border.withOpacity(0.8)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? AppColors.of(context).cyan.withOpacity(0.4)
                : AppColors.of(context).border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active
                ? AppColors.of(context).cyan
                : AppColors.of(context).textDim,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Кнопка выбора формата (xlsx / pdf)
class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).border : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? AppColors.of(context).cyan.withOpacity(0.5)
                : AppColors.of(context).border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? AppColors.of(context).cyan
                : AppColors.of(context).textDim,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Блок графика с заголовком и статистикой
