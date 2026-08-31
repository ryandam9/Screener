import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'panels.dart';

/// The categories a list is narrowed to.
///
/// An empty set means no restriction, which is what the page starts with and
/// what "All" puts back.
class FacetSelection {
  const FacetSelection({this.categories = const {}});

  final Set<String> categories;

  bool get isEmpty => categories.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// How many chips are on — what the badge counts.
  int get length => categories.length;
}

/// One multi-select facet, such as the categories a fund holds.
///
/// Multi-select rather than a single choice because the cuts worth making are
/// unions: precious *and* industrial metals, or metals *and* crypto. Nothing
/// selected means no restriction, which the leading "All" chip both says and
/// undoes.
class FacetSection extends StatelessWidget {
  const FacetSection({
    super.key,
    required this.title,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.labelOf,
  });

  final String title;
  final List<String> values;
  final Set<String> selected;

  /// Called with the value and whether it is now on.
  final void Function(String value, bool selected) onChanged;

  /// Turns a published value into its chip label — categories arrive in
  /// lower case.
  final String Function(String value)? labelOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          caption: selected.isEmpty ? null : '${selected.length} selected',
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: selected.isEmpty,
                onSelected: (_) {
                  for (final value in selected.toList()) {
                    onChanged(value, false);
                  }
                },
              ),
              for (final value in values)
                FilterChip(
                  label: Text(labelOf?.call(value) ?? value),
                  selected: selected.contains(value),
                  onSelected: (on) => onChanged(value, on),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The category sheet, for a list whose only filter is that one.
///
/// The market list builds its own sheet from [FacetSection] instead, because
/// there the facet sits among a sort order, an exchange and a minimum change.
/// Returns null when the sheet is dismissed without applying.
Future<FacetSelection?> showFacetFilterSheet(
  BuildContext context, {
  required List<String> categories,
  required FacetSelection selection,
}) {
  final chosenCategories = selection.categories.toSet();

  return showModalBottomSheet<FacetSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (builderContext, setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (categories.isNotEmpty)
                    FacetSection(
                      title: 'Category',
                      values: categories,
                      selected: chosenCategories,
                      labelOf: Fmt.titleCase,
                      onChanged: (value, on) => setSheetState(() {
                        if (on) {
                          chosenCategories.add(value);
                        } else {
                          chosenCategories.remove(value);
                        }
                      }),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(
                              sheetContext,
                            ).pop(const FacetSelection()),
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(sheetContext).pop(
                              FacetSelection(categories: chosenCategories),
                            ),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
