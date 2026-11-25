import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/desktop/mini_map_popover.dart';
import 'package:Kelivo/features/home/widgets/mini_map_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  for (final desktop in [false, true]) {
    for (final selecting in [false, true]) {
      testWidgets(
        'map opens chat find only in browse mode (desktop=$desktop, selecting=$selecting)',
        (tester) async {
          final anchor = GlobalKey();
          var opened = 0;
          final messages = [
            ChatMessage(
              role: 'user',
              conversationId: 'c',
              content: 'visible row',
            ),
          ];
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Align(
                    alignment: Alignment.bottomCenter,
                    child: TextButton(
                      key: anchor,
                      onPressed: () {
                        if (desktop) {
                          showDesktopMiniMapPopover(
                            context,
                            anchorKey: anchor,
                            messages: messages,
                            selecting: selecting,
                            selectedMessageIds: {},
                            onToggleSelection: (_) {},
                            onOpenConversationFind: () => opened++,
                          );
                        } else {
                          showMiniMapSheet(
                            context,
                            messages,
                            selecting: selecting,
                            selectedMessageIds: {},
                            onToggleSelection: (_) {},
                            onOpenConversationFind: () => opened++,
                          );
                        }
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final entry = find.byKey(const ValueKey('miniMapSearchButton'));
          expect(find.text('visible row'), findsOneWidget);
          expect(find.byType(EditableText), findsNothing);
          if (selecting) {
            expect(entry, findsNothing);
          } else {
            await tester.tap(entry);
            await tester.pumpAndSettle();
            expect(opened, 1);
            expect(find.text('visible row'), findsNothing);
          }
        },
      );
    }
    testWidgets(
      'minimap search previews and selects a match (desktop=$desktop)',
      (tester) async {
        if (!desktop) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 720);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
        }
        final stale = StreamController<List<ConversationFindPreview>>();
        final latest = StreamController<List<ConversationFindPreview>>();
        final searched = <String>[];
        final picks = <MiniMapSelection?>[];
        bool Function()? isOldSearchCurrent;
        await _openMap(
          tester,
          desktop: desktop,
          onFind: () => fail('Minimap search must stay in the map'),
          onSelect: picks.add,
          onSearch: (query, worker) {
            searched.add(query);
            if (query == 'old') {
              isOldSearchCurrent = () => worker.isCurrent;
              return stale.stream;
            }
            return latest.stream;
          },
        );
        await tester.tap(_filterButton);
        await tester.pumpAndSettle();
        final field = find.byType(EditableText);
        expect(find.text('visible row'), findsOneWidget);
        if (!desktop) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
        }
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '知',
            selection: TextSelection.collapsed(offset: 1),
            composing: TextRange(start: 0, end: 1),
          ),
        );
        await tester.pump(const Duration(milliseconds: 240));
        expect(searched, isEmpty);
        await tester.enterText(field, 'old');
        await tester.pump(const Duration(milliseconds: 200));
        expect(isOldSearchCurrent!(), isTrue);
        await tester.enterText(field, '知豆');
        await tester.pump(const Duration(milliseconds: 200));
        expect(isOldSearchCurrent!(), isFalse);
        expect(searched, ['old', '知豆']);
        latest.add([_preview(0, '知豆', matchCount: 3), _preview(1, '知豆')]);
        stale.add([_preview(0, 'old')]);
        unawaited(stale.close());
        await tester.pump();
        expect(find.text('M0 old context'), findsNothing);
        expect(find.text('M0 知豆 context'), findsOneWidget);
        expect(find.text('M1 知豆 context'), findsOneWidget);
        expect(find.text('3 matches').hitTestable(), findsOneWidget);
        expect(find.text('1 match').hitTestable(), findsOneWidget);
        expect(picks, isEmpty);
        latest.add([for (var i = 2; i < 40; i++) _preview(i, '知豆')]);
        unawaited(latest.close());
        if (!desktop) tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final result = find.text('M39 知豆 context');
        await tester.scrollUntilVisible(
          result,
          120,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('miniMapSearchResults')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(result);
        await tester.pumpAndSettle();
        expect(picks.single?.match, _preview(39, '知豆').hit);
        expect(field, findsNothing);
      },
    );
  }
}
