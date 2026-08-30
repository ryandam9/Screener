import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'panels.dart';

/// The categories and issuers a list is narrowed to.
///
/// Empty sets mean no restriction, which is what both pages start with and
/// what "All" puts back.
class FacetSelection {
  const FacetSelection({this.categories = const {}, this.issuers = const {}});

  final Set<String> categories;
  final Set<String> issuers;

  bool get isEmpty => categories.isEmpty && issuers.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// How many chips are on, across both facets — what the badge counts.
  int get length => categories.length + issuers.length;
}

/// One multi-select facet: the categories a fund holds, or the issuers that
/// run them.
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

  /// Turns a published value into its chip label. Categories arrive in lower
  /// case; issuers are already spelled the way the fund spells itself.
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

/// The category-and-issuer sheet, for a list whose only filters are these two.
///
/// The market list builds its own sheet from [FacetSection] instead, because
/// there the facets sit among a sort order, an exchange and a minimum change.
/// Returns null when the sheet is dismissed without applying.
Future<FacetSelection?> showFacetFilterSheet(
  BuildContext context, {
  required List<String> categories,
  required List<String> issuers,
  required FacetSelection selection,
}) {
  final chosenCategories = selection.categories.toSet();
  final chosenIssuers = selection.issuers.toSet();

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
                  if (issuers.isNotEmpty)
                    FacetSection(
                      title: 'Issuer',
                      values: issuers,
                      selected: chosenIssuers,
                      onChanged: (value, on) => setSheetState(() {
                        if (on) {
                          chosenIssuers.add(value);
                        } else {
                          chosenIssuers.remove(value);
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
                              FacetSelection(
                                categories: chosenCategories,
                                issuers: chosenIssuers,
                              ),
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
