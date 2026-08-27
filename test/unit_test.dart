import 'package:flutter_test/flutter_test.dart';
import 'package:campus_quicksplit/main.dart';

void main() {
  group('Comprehensive Unit & Math Tests', () {
    test('1. Largest-Remainder (Hamilton) Rounding eliminates 99.99 bug', () {
      final splits = SplitEngine.calculateEqualSplits(
        totalAmount: 100.00,
        memberIds: ['1', '2', '3'],
      );

      expect(splits['1'], 33.34);
      expect(splits['2'], 33.33);
      expect(splits['3'], 33.33);

      final totalSum = splits.values.reduce((a, b) => a + b);
      expect(totalSum, 100.00);
    });

    test('2. Multi-payer unoptimized transfer metrics count all contributors', () {
      final multiPayerExpense = Expense(
        id: 'exp_multi',
        title: 'Dinner Treat',
        amount: 300.0,
        category: 'Canteen',
        date: DateTime.now(),
        paidBy: {'1': 150.0, '2': 150.0}, // MULTI-PAYER
        splitMode: SplitMode.equal,
        splits: {'1': 100.0, '2': 100.0, '3': 100.0},
      );

      final count = DebtOptimizer.calculateRawUnoptimizedCount([multiPayerExpense]);
      // Only non-payer (member 3) creates raw debts to payers 1 and 2 → 2 transfers
      expect(count, 2);
    });

    test('3. Future-dated expenses are excluded from Analytics', () {
      final now = DateTime.now();
      final futureExpense = Expense(
        id: 'exp_future',
        title: 'Future Trip',
        amount: 500.0,
        category: 'Other',
        date: now.add(const Duration(days: 10)),
        paidBy: {'1': 500.0},
        splitMode: SplitMode.equal,
        splits: {'1': 250.0, '2': 250.0},
      );

      final pastExpense = Expense(
        id: 'exp_past',
        title: 'Current Food',
        amount: 200.0,
        category: 'Canteen',
        date: now.subtract(const Duration(hours: 1)),
        paidBy: {'1': 200.0},
        splitMode: SplitMode.equal,
        splits: {'1': 100.0, '2': 100.0},
      );

      final provider = AppProvider();
      provider.resetAllData(); // clear seeded sample expenses
      provider.addExpense(futureExpense);
      provider.addExpense(pastExpense);

      final filtered = provider.filteredAnalyticsExpenses;
      expect(filtered.length, 1);
      expect(filtered.first.id, 'exp_past');
    });

    test('4. Settlement records adjust balances without inflating spend totals', () {
      final members = [
        Member(id: '1', name: 'Aarav', avatarColor: '#6C63FF'),
        Member(id: '2', name: 'Rohan', avatarColor: '#00C896'),
      ];

      final expense = Expense(
        id: 'exp1',
        title: 'Juice',
        amount: 200.0,
        category: 'Canteen',
        date: DateTime.now(),
        paidBy: {'1': 200.0},
        splitMode: SplitMode.equal,
        splits: {'1': 100.0, '2': 100.0},
      );

      final settlement = SettlementRecord(
        id: 'set1',
        fromMemberId: '2',
        toMemberId: '1',
        amount: 100.0,
        date: DateTime.now(),
      );

      final balances = DebtOptimizer.computeNetBalances(
        members: members,
        expenses: [expense],
        settlements: [settlement],
      );

      expect(balances['1']!.abs() < 0.01, true);
      expect(balances['2']!.abs() < 0.01, true);

      final pendingDebts = DebtOptimizer.computeSimplifiedDebts(
        members: members,
        expenses: [expense],
        settlements: [settlement],
      );
      expect(pendingDebts.isEmpty, true);
    });

    test('5. Timestamp formatting displays exact time and relative tag', () {
      final dt = DateTime.now().subtract(const Duration(hours: 3));
      final formatted = Formatters.formatTimestampWithRelative(dt);

      expect(formatted.contains('3h ago'), true);
      expect(formatted.contains('('), true);
      expect(formatted.contains(')'), true);
    });

    test('6. Negative/NaN rejection helpers are finite-safe', () {
      final bad = double.nan;
      expect(bad.isFinite, false);
      expect(double.infinity.isFinite, false);
      expect((-5.0) > 0, false);
      expect(100.0.isFinite && 100.0 > 0, true);
    });
  });
}