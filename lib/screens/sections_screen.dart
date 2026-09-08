import 'package:flutter/material.dart';

import '../modules/registry.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/pill_switch.dart';
import '../theme/app_metrics.dart';

/// Dove si decide cosa si guarda.
///
/// Ricalca la sezione PANNELLI delle opzioni del desktop: i moduli accesi
/// raggruppati per sezione, quelli spenti in fondo, un interruttore per
/// riga e la maniglia per riordinare. Con una differenza che viene dallo
/// schermo: li' le sezioni sono tre colonne fisse, qui se ne creano quante
/// se ne vuole, perche' su un telefono si scorre di lato e non c'e' un
/// limite di larghezza da rispettare.
class SectionsScreen extends StatefulWidget {
  const SectionsScreen({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<SectionsScreen> createState() => _SectionsScreenState();
}

class _SectionsScreenState extends State<SectionsScreen> {
  SettingsService get settings => widget.settings;

  @override
  Widget build(BuildContext context) {
    final off = moduleRegistry.keys.where((id) => !settings.isOn(id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sezioni'),
        actions: [
          IconButton(
            tooltip: 'Nuova sezione',
            icon: const Icon(Icons.add),
            onPressed: _askNewSection,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppMetrics.cardPadding),
        children: [
          for (var index = 0; index < settings.sections.length; index++)
            _sectionBlock(index),
          if (off.isNotEmpty) ...[
            const SizedBox(height: AppMetrics.gap),
            const _Label('SPENTI'),
            for (final id in off)
              _ModuleRow(
                title: moduleRegistry[id]!.title,
                on: false,
                onToggle: () async {
                  await settings.toggle(id);
                  setState(() {});
                },
              ),
          ],
          const SizedBox(height: AppMetrics.gap * 2),
          const Text(
            'Un modulo spento non viene nemmeno chiesto al PC: quello che non si '
            'guarda non si scarica.',
            style: TextStyle(color: AppColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sectionBlock(int index) {
    final section = settings.sections[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppMetrics.gap),
        Row(
          children: [
            Expanded(child: _Label(section.name.toUpperCase())),
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, color: AppColors.faint),
              onPressed: () => _askRename(index),
            ),
            if (settings.sections.length > 1)
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, color: AppColors.faint),
                onPressed: () => _confirmRemove(index),
              ),
          ],
        ),
        if (section.modules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppMetrics.gapSmall),
            child: Text('vuota',
                style: TextStyle(color: AppColors.faint, fontSize: 11)),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (from, to) async {
              final id = section.modules[from];
              await settings.moveModule(id, section.name, to > from ? to - 1 : to);
              setState(() {});
            },
            children: [
              for (var position = 0; position < section.modules.length; position++)
                _ModuleRow(
                  key: ValueKey('${section.name}/${section.modules[position]}'),
                  title: moduleRegistry[section.modules[position]]?.title ??
                      section.modules[position],
                  on: true,
                  dragIndex: position,
                  onToggle: () async {
                    await settings.toggle(section.modules[position]);
                    setState(() {});
                  },
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _askNewSection() async {
    final name = await _askText('Nuova sezione', '');
    if (name != null) {
      await settings.addSection(name);
      setState(() {});
    }
  }

  Future<void> _askRename(int index) async {
    final name = await _askText('Rinomina', settings.sections[index].name);
    if (name != null) {
      await settings.renameSection(index, name);
      setState(() {});
    }
  }

  Future<void> _confirmRemove(int index) async {
    final section = settings.sections[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Eliminare «${section.name}»?'),
        content: Text(
          section.modules.isEmpty
              ? 'È vuota.'
              : 'I ${section.modules.length} moduli che contiene si spengono.',
          style: const TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.urgent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.removeSection(index);
      setState(() {});
    }
  }

  Future<String?> _askText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.foreground),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Va bene'),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 10,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
        ),
      );
}

/// Una riga del catalogo: maniglia, interruttore, nome. L'interruttore e'
/// quello del desktop — 32x18, acceso pieno blu con bordo chiaro, spento
/// grigio su grigio — perche' e' lo stesso gesto sulla stessa cosa.
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    super.key,
    required this.title,
    required this.on,
    required this.onToggle,
    this.dragIndex,
  });

  final String title;
  final bool on;
  final VoidCallback onToggle;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: const Padding(
                  padding: EdgeInsets.only(right: AppMetrics.gapSmall),
                  child: Icon(Icons.drag_indicator, size: 18, color: AppColors.faint),
                ),
              )
            else
              const SizedBox(width: 26),
            PillSwitch(on: on),
            const SizedBox(width: AppMetrics.gap),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: on ? AppColors.foreground : AppColors.disabled,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
