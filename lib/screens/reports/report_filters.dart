part of '../reports_screen.dart';

class _CompanyFilterBlock extends StatelessWidget {
  const _CompanyFilterBlock({
    required this.searchController,
    required this.searchQuery,
    required this.filteredLocations,
    required this.selectedLocationId,
    required this.labelSuffix,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onLocationChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final List<LocationModel> filteredLocations;
  final int? selectedLocationId;
  final String labelSuffix;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<int?> onLocationChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Поле поиска
        TextField(
          controller: searchController,
          style: TextStyle(color: c.textMain, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Поиск по компании...',
            hintStyle: TextStyle(color: c.textDim, fontSize: 12),
            prefixIcon: Icon(Icons.search, color: c.textDim, size: 18),
            suffixIcon: searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: onSearchCleared,
                    child: Icon(Icons.close, color: c.textDim, size: 18),
                  )
                : null,
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
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 8),
        if (filteredLocations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Компании не найдены',
              style: TextStyle(color: c.textDim, fontSize: 12),
            ),
          )
        else
          _StyledDropdown<int>(
            label: 'Компания$labelSuffix',
            value: filteredLocations.any((l) => l.id == selectedLocationId)
                ? selectedLocationId
                : filteredLocations.first.id,
            items: filteredLocations
                .map(
                  (l) => DropdownMenuItem(
                    value: l.id,
                    child: Text(l.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: onLocationChanged,
          ),
      ],
    );
  }
}

/// Карточка-секция с общим фоном и бордером
