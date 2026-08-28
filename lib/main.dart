// ============================================================================
// 1. IMPORTS
// ============================================================================
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

// ============================================================================
// 2. THEME & COLORS
// ============================================================================
class AppColors {
  static const Color teal = Color(0xFF14B8A6);
  static const Color primary = Color(0xFF2C6BED);
  static const Color primaryGlow = Color(0x332C6BED);
  static const Color success = Color(0xFF22C55E);
  static const Color successGlow = Color(0x2022C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerGlow = Color(0x20EF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color accent = Color(0xFF38BDF8);

  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightSurface = Color(0xFFF1F5F9);
  static const Color lightText = Color(0xFF0F172A);
  static const Color neutralBlack = Color(0xFF0F172A);
  static const Color neutralGray = Color(0xFF64748B);
  static const Color pillBg = Color(0xFFEEF2F6);

  static const Color darkBg = Color(0xFF070B14);
  static const Color darkCard = Color(0xFF0F172A);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Map<String, Color> categoryColors = {
    'Canteen': Color(0xFFFF6584),
    'Chai & Snacks': Color(0xFFFFB84C),
    'Auto': Color(0xFF38BDF8),
    'Xerox': Color(0xFFA78BFA),
    'Mess': Color(0xFF00C896),
    'Subscriptions': Color(0xFFF43F5E),
    'Groceries': Color(0xFF34D399),
    'Other': Color(0xFF818CF8),
  };

  static const Map<String, dynamic> categoryFaIcons = {
    'Canteen': FontAwesomeIcons.utensils,
    'Chai & Snacks': FontAwesomeIcons.mugSaucer,
    'Auto': FontAwesomeIcons.car,
    'Xerox': FontAwesomeIcons.print,
    'Mess': FontAwesomeIcons.bowlRice,
    'Subscriptions': FontAwesomeIcons.film,
    'Groceries': FontAwesomeIcons.basketShopping,
    'Other': FontAwesomeIcons.tags,
  };
}

// ============================================================================
// 3. ENUMS
// ============================================================================
enum SplitMode { equal, exact, percentage }
enum AnalyticsTimeframe { week, month, allTime }

// ============================================================================
// 4. DATA MODELS
// ============================================================================
class Member {
  final String id;
  final String name;
  final int avatarColorValue;
  final String upiId;

  Member({
    required this.id,
    required this.name,
    int? avatarColorValue,
    Color? avatarColor,
    String? upiId,
  })  : avatarColorValue = avatarColorValue ?? (avatarColor?.toARGB32() ?? 0xFF2C6BED),
        upiId = upiId ?? '';

  Color get avatarColor => Color(avatarColorValue);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'avatarColorValue': avatarColorValue,
    'upiId': upiId,
  };

  factory Member.fromMap(Map<String, dynamic> map) => Member(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    avatarColorValue: map['avatarColorValue'] ?? 0xFF2C6BED,
    upiId: map['upiId'] ?? '',
  );
}

class Expense {
  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final Map<String, double> paidBy;
  final SplitMode splitMode;
  final Map<String, double> splits;
  final String note;
  final bool isSettlement;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.paidBy,
    required this.splitMode,
    required this.splits,
    this.note = '',
    this.isSettlement = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
    'paidBy': paidBy,
    'splitMode': splitMode.index,
    'splits': splits,
    'note': note,
    'isSettlement': isSettlement,
  };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
    id: map['id'] ?? '',
    title: map['title'] ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    category: map['category'] ?? 'Other',
    date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
    paidBy: Map<String, double>.from(
      (map['paidBy'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      ),
    ),
    splitMode: SplitMode.values[(map['splitMode'] as int?) ?? 0],
    splits: Map<String, double>.from(
      (map['splits'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      ),
    ),
    note: map['note'] ?? '',
    isSettlement: map['isSettlement'] ?? false,
  );
}

class SettlementRecord {
  final String id;
  final String fromMemberId;
  final String toMemberId;
  final double amount;
  final DateTime date;

  SettlementRecord({
    required this.id,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'fromMemberId': fromMemberId,
    'toMemberId': toMemberId,
    'amount': amount,
    'date': date.toIso8601String(),
  };

  factory SettlementRecord.fromMap(Map<String, dynamic> map) => SettlementRecord(
    id: map['id'] ?? '',
    fromMemberId: map['fromMemberId'] ?? '',
    toMemberId: map['toMemberId'] ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
  );
}

class SimplifiedDebt {
  final String fromMemberId;
  final String toMemberId;
  final double amount;

  SimplifiedDebt({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
  });
}

class GroupItem {
  final String id;
  final String name;
  final int membersCount;
  final String category;
  final int colorValue;
  final String status;
  final double amount;
  final List<String> details;

  GroupItem({
    required this.id,
    required this.name,
    required this.membersCount,
    required this.category,
    required this.colorValue,
    required this.status,
    required this.amount,
    required this.details,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'membersCount': membersCount,
    'category': category,
    'colorValue': colorValue,
    'status': status,
    'amount': amount,
    'details': details,
  };

  factory GroupItem.fromMap(Map<String, dynamic> map) => GroupItem(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    membersCount: map['membersCount'] ?? 1,
    category: map['category'] ?? 'Home',
    colorValue: map['colorValue'] ?? 0xFF2C6BED,
    status: map['status'] ?? 'settled',
    amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    details: List<String>.from(map['details'] ?? []),
  );
}

// ============================================================================
// 5. ENGINES & ALGORITHMS
// ============================================================================
class SplitEngine {
  /// Hamilton Largest Remainder Rule (Exact integer paise split)
  static Map<String, double> calculateEqualSplits({
    required double totalAmount,
    required List<String> memberIds,
  }) {
    if (memberIds.isEmpty || totalAmount <= 0) return {};

    final int totalPaise = (totalAmount * 100).round();
    final int n = memberIds.length;
    final int basePaise = totalPaise ~/ n;
    final int remainderPaise = totalPaise % n;

    final Map<String, double> splits = {};
    for (int i = 0; i < n; i++) {
      final int paise = basePaise + (i < remainderPaise ? 1 : 0);
      splits[memberIds[i]] = paise / 100.0;
    }
    return splits;
  }
}

class DebtOptimizer {
  static Map<String, double> computeNetBalances(
    List<Member> members,
    List<Expense> expenses, [
    List<SettlementRecord> settlements = const [],
  ]) {
    final Map<String, double> balances = {for (var m in members) m.id: 0.0};

    for (final exp in expenses) {
      if (exp.isSettlement) continue;
      exp.paidBy.forEach((payerId, amt) {
        balances[payerId] = (balances[payerId] ?? 0.0) + amt;
      });
      exp.splits.forEach((borrowerId, owedAmt) {
        balances[borrowerId] = (balances[borrowerId] ?? 0.0) - owedAmt;
      });
    }

    for (final s in settlements) {
      balances[s.fromMemberId] = (balances[s.fromMemberId] ?? 0.0) + s.amount;
      balances[s.toMemberId] = (balances[s.toMemberId] ?? 0.0) - s.amount;
    }

    return balances;
  }

  static List<SimplifiedDebt> computeSimplifiedDebts(
    List<Member> members,
    List<Expense> expenses, [
    List<SettlementRecord> settlements = const [],
  ]) {
    if (members.isEmpty) return [];
    final balances = computeNetBalances(members, expenses, settlements);

    final List<MapEntry<String, double>> debtors = [];
    final List<MapEntry<String, double>> creditors = [];

    balances.forEach((id, net) {
      if (net < -0.009) debtors.add(MapEntry(id, net));
      if (net > 0.009) creditors.add(MapEntry(id, net));
    });

    debtors.sort((a, b) => a.value.compareTo(b.value));
    creditors.sort((a, b) => b.value.compareTo(a.value));

    final Map<String, double> tempBalances = Map.from(balances);
    final List<SimplifiedDebt> result = [];

    int dIdx = 0;
    int cIdx = 0;

    while (dIdx < debtors.length && cIdx < creditors.length) {
      final debtorId = debtors[dIdx].key;
      final creditorId = creditors[cIdx].key;

      final debtorDebt = -tempBalances[debtorId]!;
      final creditorCredit = tempBalances[creditorId]!;

      final transferAmount = math.min(debtorDebt, creditorCredit);
      final roundedTransfer = (transferAmount * 100).round() / 100.0;

      if (roundedTransfer > 0.009) {
        result.add(
          SimplifiedDebt(
            fromMemberId: debtorId,
            toMemberId: creditorId,
            amount: roundedTransfer,
          ),
        );
      }

      tempBalances[debtorId] = tempBalances[debtorId]! + transferAmount;
      tempBalances[creditorId] = tempBalances[creditorId]! - transferAmount;

      if (tempBalances[debtorId]!.abs() < 0.009) dIdx++;
      if (tempBalances[creditorId]!.abs() < 0.009) cIdx++;
    }

    return result;
  }

  static int calculateRawUnoptimizedCount(
    List<dynamic> membersOrExpenses, [
    List<Expense>? expenses,
  ]) {
    final List<Expense> expList = expenses ?? (membersOrExpenses.whereType<Expense>().toList());
    int count = 0;

    for (final exp in expList) {
      if (exp.isSettlement) continue;

      final Set<String> allMembers = {...exp.paidBy.keys, ...exp.splits.keys};
      int overpayers = 0;
      int underpayers = 0;

      for (final id in allMembers) {
        final paid = exp.paidBy[id] ?? 0.0;
        final owed = exp.splits[id] ?? 0.0;
        if (paid - owed > 0.009) {
          overpayers++;
        } else if (owed - paid > 0.009) {
          underpayers++;
        }
      }

      count += (overpayers * underpayers);
    }

    return count;
  }
}

// ============================================================================
// 6. APP PROVIDER
// ============================================================================
class AppProvider extends ChangeNotifier {
  Box? _box;

  List<Member> _members = [];
  List<Expense> _expenses = [];
  List<SettlementRecord> _settlements = [];
  List<GroupItem> _groups = [];

  int _currentTab = 0;
  ThemeMode _themeMode = ThemeMode.dark;
  Expense? _lastDeletedExpense;

  List<Member> get members => _members;
  List<Expense> get expenses => _expenses;
  List<Expense> get filteredAnalyticsExpenses => _expenses
      .where((e) => !e.isSettlement && !e.date.isAfter(DateTime.now()))
      .toList();
  List<SettlementRecord> get settlements => _settlements;
  List<GroupItem> get groups => _groups;
  int get currentTab => _currentTab;
  ThemeMode get themeMode => _themeMode;
  Expense? get lastDeletedExpense => _lastDeletedExpense;

  String getMemberName(String id) =>
      _members.firstWhere((m) => m.id == id, orElse: () => Member(id: id, name: 'Member', avatarColorValue: 0xFF2C6BED, upiId: '')).name;

  Member? getMember(String id) =>
      _members.cast<Member?>().firstWhere((m) => m?.id == id, orElse: () => null);

  double get myNetBalance {
    final balances = DebtOptimizer.computeNetBalances(_members, _expenses, _settlements);
    return balances['1'] ?? 0.0;
  }

  List<SimplifiedDebt> get pendingSettlements =>
      DebtOptimizer.computeSimplifiedDebts(_members, _expenses, _settlements);

  double get todaySpending {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return _expenses
        .where((e) => !e.isSettlement && e.date.isAfter(startOfDay))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get thisMonthSpending {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    return _expenses
        .where((e) => !e.isSettlement && e.date.isAfter(startOfMonth))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> init() async {
    final box = await Hive.openBox('campus_quicksplit_db');
    _box = box;

    final isDark = box.get('isDarkTheme', defaultValue: true);
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

    final savedMembers = box.get('members');
    if (savedMembers != null) {
      _members = (jsonDecode(savedMembers) as List)
          .map((m) => Member.fromMap(m))
          .toList();
    } else {
      _members = [
        Member(id: '1', name: 'Aarav (You)', avatarColorValue: 0xFF2C6BED, upiId: 'aarav@okaxis'),
        Member(id: '2', name: 'Rohan', avatarColorValue: 0xFF22C55E, upiId: 'rohan@oksbi'),
        Member(id: '3', name: 'Priya', avatarColorValue: 0xFFFF6584, upiId: 'priya@okicici'),
        Member(id: '4', name: 'Kabir', avatarColorValue: 0xFFF59E0B, upiId: 'kabir@paytm'),
      ];
      _saveMembers();
    }

    final savedExpenses = box.get('expenses');
    if (savedExpenses != null) {
      _expenses = (jsonDecode(savedExpenses) as List)
          .map((e) => Expense.fromMap(e))
          .toList();
    } else {
      final now = DateTime.now();
      _expenses = [
        Expense(
          id: 'exp-1',
          title: 'Campus Canteen Thali & Juice',
          amount: 480.0,
          category: 'Canteen',
          date: now.subtract(const Duration(hours: 3)),
          paidBy: const {'1': 480.0},
          splitMode: SplitMode.equal,
          splits: SplitEngine.calculateEqualSplits(totalAmount: 480.0, memberIds: const ['1', '2', '3', '4']),
          note: 'Post mid-sem treat',
        ),
        Expense(
          id: 'exp-2',
          title: 'Shared Auto to Metro',
          amount: 120.0,
          category: 'Auto',
          date: now.subtract(const Duration(hours: 24)),
          paidBy: const {'2': 120.0},
          splitMode: SplitMode.equal,
          splits: SplitEngine.calculateEqualSplits(totalAmount: 120.0, memberIds: const ['1', '2', '4']),
          note: 'Evening commute',
        ),
        Expense(
          id: 'exp-3',
          title: 'Lab Manual Xerox & Binding',
          amount: 250.0,
          category: 'Xerox',
          date: now.subtract(const Duration(hours: 48)),
          paidBy: const {'3': 250.0},
          splitMode: SplitMode.equal,
          splits: SplitEngine.calculateEqualSplits(totalAmount: 250.0, memberIds: const ['1', '2', '3', '4']),
        ),
      ];
      _saveExpenses();
    }

    final savedGroups = box.get('groups');
    if (savedGroups != null) {
      _groups = (jsonDecode(savedGroups) as List)
          .map((g) => GroupItem.fromMap(g))
          .toList();
    } else {
      _groups = [
        GroupItem(
          id: 'grp-1',
          name: 'MyHome',
          membersCount: 3,
          category: 'Home',
          colorValue: 0xFF2C6BED,
          status: 'owed',
          amount: 15565.73,
          details: const ['Aman pays you ₹11,830.77', 'Rohit pays you ₹3,734.96'],
        ),
        GroupItem(
          id: 'grp-2',
          name: 'Manali Trip',
          membersCount: 6,
          category: 'Trip',
          colorValue: 0xFF14B8A6,
          status: 'settled',
          amount: 0,
          details: const ['All trip expenditures balanced'],
        ),
        GroupItem(
          id: 'grp-3',
          name: 'Flat 402',
          membersCount: 4,
          category: 'Flat',
          colorValue: 0xFFFF8C42,
          status: 'owe',
          amount: 1077.99,
          details: const ['Wi-Fi bill & Cook contribution pending'],
        ),
      ];
      _saveGroups();
    }

    final savedSettlements = box.get('settlements');
    if (savedSettlements != null) {
      _settlements = (jsonDecode(savedSettlements) as List)
          .map((s) => SettlementRecord.fromMap(s))
          .toList();
    }

    notifyListeners();
  }

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _box?.put('isDarkTheme', _themeMode == ThemeMode.dark);
    notifyListeners();
  }

  void addExpense(Expense exp) {
    _expenses.insert(0, exp);
    _saveExpenses();
    notifyListeners();
  }

  void deleteExpense(String id) {
    final idx = _expenses.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _lastDeletedExpense = _expenses[idx];
      _expenses.removeAt(idx);
      _saveExpenses();
      notifyListeners();
    }
  }

  void undoDelete() {
    if (_lastDeletedExpense != null) {
      _expenses.insert(0, _lastDeletedExpense!);
      _lastDeletedExpense = null;
      _saveExpenses();
      notifyListeners();
    }
  }

  void settleDebt(String fromId, String toId, double amount) {
    final record = SettlementRecord(
      id: 'settle-${const Uuid().v4()}',
      fromMemberId: fromId,
      toMemberId: toId,
      amount: amount,
      date: DateTime.now(),
    );
    _settlements.insert(0, record);

    final fromName = getMemberName(fromId);
    final toName = getMemberName(toId);

    final settleExpense = Expense(
      id: 'exp-${const Uuid().v4()}',
      title: 'Settled: $fromName → $toName',
      amount: amount,
      category: 'Other',
      date: DateTime.now(),
      paidBy: {fromId: amount},
      splitMode: SplitMode.exact,
      splits: {toId: amount},
      note: 'Marked as settled via UPI',
      isSettlement: true,
    );

    _expenses.insert(0, settleExpense);
    _saveSettlements();
    _saveExpenses();
    notifyListeners();
  }

  void addGroup(String name, String category) {
    const colors = [0xFF2C6BED, 0xFF14B8A6, 0xFFFF8C42, 0xFFEC4899, 0xFF8B5CF6];
    final newGroup = GroupItem(
      id: 'grp-${const Uuid().v4()}',
      name: name,
      membersCount: _members.length,
      category: category,
      colorValue: colors[_groups.length % colors.length],
      status: 'settled',
      amount: 0,
      details: const ['Newly created group'],
    );
    _groups.insert(0, newGroup);
    _saveGroups();
    notifyListeners();
  }

  void addMember(String name, String upiId) {
    const colors = [0xFF2C6BED, 0xFF22C55E, 0xFFFF6584, 0xFFF59E0B, 0xFF38BDF8, 0xFFA78BFA];
    final newMember = Member(
      id: '${_members.length + 1}',
      name: name,
      avatarColorValue: colors[_members.length % colors.length],
      upiId: upiId,
    );
    _members.add(newMember);
    _saveMembers();
    notifyListeners();
  }

  void resetAllData() {
    _expenses.clear();
    _settlements.clear();
    _saveExpenses();
    _saveSettlements();
    notifyListeners();
  }

  void _saveMembers() => _box?.put('members', jsonEncode(_members.map((m) => m.toMap()).toList()));
  void _saveExpenses() => _box?.put('expenses', jsonEncode(_expenses.map((e) => e.toMap()).toList()));
  void _saveGroups() => _box?.put('groups', jsonEncode(_groups.map((g) => g.toMap()).toList()));
  void _saveSettlements() => _box?.put('settlements', jsonEncode(_settlements.map((s) => s.toMap()).toList()));
}

// ============================================================================
// 7. FORMATTERS HELPER
// ============================================================================
class Formatters {
  static String formatRupee(double amount) {
    final format = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  static String formatTimestampWithRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    String rel = '';
    if (diff.inMinutes < 1) {
      rel = 'Just now';
    } else if (diff.inMinutes < 60) {
      rel = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      rel = '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      rel = 'Yesterday';
    } else {
      rel = '${diff.inDays}d ago';
    }

    final exact = DateFormat('dd MMM, hh:mm a').format(date);
    return '$exact ($rel)';
  }
}

// ============================================================================
// 8. HELPERS & CUSTOM WIDGETS
// ============================================================================
Widget buildCategoryIcon(String category, {double size = 18, Color? color}) {
  final dynamic iconData = AppColors.categoryFaIcons[category] ?? FontAwesomeIcons.tags;
  final iconColor = color ?? (AppColors.categoryColors[category] ?? AppColors.primary);
  return Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: iconColor.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Center(
      child: FaIcon(iconData, size: size, color: iconColor),
    ),
  );
}

class BouncyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;

  const BouncyButton({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.94,
  });

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleFactor).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}

class AnimatedRupeeCounter extends StatelessWidget {
  final double value;
  final TextStyle? style;

  const AnimatedRupeeCounter({super.key, required this.value, this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        return Text(Formatters.formatRupee(val), style: style);
      },
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double radius;

  const DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.gap = 4.0,
    this.radius = 14.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    final Path path = Path()..addRRect(rrect);
    final Path dashPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = draw ? 6.0 : gap;
        if (draw) {
          dashPath.addPath(
            metric.extractPath(distance, distance + len),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// 8B. 3D INTERACTIVE TILT PHYSICS CARD
// ============================================================================
class Tilt3DCard extends StatefulWidget {
  final Widget child;
  final double maxTilt;

  const Tilt3DCard({
    super.key,
    required this.child,
    this.maxTilt = 0.14,
  });

  @override
  State<Tilt3DCard> createState() => _Tilt3DCardState();
}

class _Tilt3DCardState extends State<Tilt3DCard> with SingleTickerProviderStateMixin {
  double _rotX = 0.0;
  double _rotY = 0.0;
  late AnimationController _animController;
  late Animation<double> _animX;
  late Animation<double> _animY;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _resetTilt() {
    _animX = Tween<double>(begin: _rotX, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animY = Tween<double>(begin: _rotY, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _rotX = 0.0;
          _rotY = 0.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _rotX += -details.delta.dy * 0.0035;
          _rotY += details.delta.dx * 0.0035;
          _rotX = _rotX.clamp(-widget.maxTilt, widget.maxTilt);
          _rotY = _rotY.clamp(-widget.maxTilt, widget.maxTilt);
        });
      },
      onPanEnd: (_) => _resetTilt(),
      onPanCancel: () => _resetTilt(),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final x = _animController.isAnimating ? _animX.value : _rotX;
          final y = _animController.isAnimating ? _animY.value : _rotY;
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(x)
              ..rotateY(y),
            alignment: FractionalOffset.center,
            child: widget.child,
          );
        },
      ),
    );
  }
}

// ============================================================================
// 8C. DYNAMIC PROCEDURAL UPI QR CODE DIALOG
// ============================================================================
class UpiQrPainter extends CustomPainter {
  final String upiData;
  final Color color;

  const UpiQrPainter({required this.upiData, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double cellSize = size.width / 21.0;

    void drawFinderPattern(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, cellSize * 7, cellSize * 7), paint);
      canvas.drawRect(
        Rect.fromLTWH(x + cellSize, y + cellSize, cellSize * 5, cellSize * 5),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH(x + cellSize * 2, y + cellSize * 2, cellSize * 3, cellSize * 3),
        paint,
      );
    }

    drawFinderPattern(0, 0);
    drawFinderPattern(size.width - cellSize * 7, 0);
    drawFinderPattern(0, size.height - cellSize * 7);

    final int seed = upiData.hashCode;
    final random = math.Random(seed);

    for (int r = 0; r < 21; r++) {
      for (int c = 0; c < 21; c++) {
        if ((r < 7 && c < 7) || (r < 7 && c > 13) || (r > 13 && c < 7)) continue;
        if (random.nextBool()) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellSize + 0.8, r * cellSize + 0.8, cellSize - 1.6, cellSize - 1.6),
              const Radius.circular(1.5),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void showUpiQrDialog(
  BuildContext context, {
  required String receiverName,
  required String upiId,
  required double amount,
  required VoidCallback onSettled,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
  final textColor = isDark ? Colors.white : AppColors.neutralBlack;
  final upiPayload = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(receiverName)}&am=$amount&cu=INR';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Scan to Settle via UPI',
            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan using PhonePe, GPay, Paytm, or BHIM',
            style: GoogleFonts.inter(fontSize: 12, color: isDark ? AppColors.textMuted : AppColors.neutralGray),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox(
              width: 170,
              height: 170,
              child: CustomPaint(
                painter: UpiQrPainter(
                  upiData: upiPayload,
                  color: AppColors.neutralBlack,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            Formatters.formatRupee(amount),
            style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const SizedBox(height: 2),
          Text(
            'To: $receiverName ($upiId)',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: upiId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied UPI ID: $upiId')),
                    );
                  },
                  icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
                  label: const Text('Copy UPI'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onSettled();
                  },
                  icon: const FaIcon(FontAwesomeIcons.check, size: 12),
                  label: const Text('Mark Settled'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

// ============================================================================
// 9. CLEAN BOTTOM NAV
// ============================================================================
class CleanBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const CleanBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    const items = [
      {'icon': FontAwesomeIcons.house, 'label': 'Home'},
      {'icon': FontAwesomeIcons.users, 'label': 'Groups'},
      {'icon': FontAwesomeIcons.chartSimple, 'label': 'Analytics'},
      {'icon': FontAwesomeIcons.fileLines, 'label': 'Bills'},
      {'icon': FontAwesomeIcons.wallet, 'label': 'Balances'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(top: BorderSide(color: border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final isSelected = currentIndex == i;
              final color = isSelected ? AppColors.primary : (isDark ? AppColors.textMuted : AppColors.neutralGray);

              return BouncyButton(
                onTap: () => onTabSelected(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: FaIcon(
                          items[i]['icon'] as dynamic,
                          size: 16,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i]['label'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 10. SPLASH SCREEN (TYPEWRITER EFFECT)
// ============================================================================
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _fullText = 'Campus QuickSplit';
  String _displayedText = '';
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTypewriter();
  }

  void _startTypewriter() async {
    while (_charIndex < _fullText.length) {
      await Future.delayed(const Duration(milliseconds: 65));
      if (!mounted) return;
      setState(() {
        _charIndex++;
        _displayedText = _fullText.substring(0, _charIndex);
      });
    }

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: FaIcon(FontAwesomeIcons.bolt, color: Colors.white, size: 32),
              ),
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayedText,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 2,
                  height: 24,
                  color: AppColors.primary,
                ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 400.ms),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Split Smart • Settle Fast',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 11. MAIN SHELL SCREEN
// ============================================================================
class MainShellScreen extends StatelessWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    const screens = [
      DashboardScreen(),
      GroupsScreen(),
      AnalyticsScreen(),
      BillsScreen(),
      BalancesScreen(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey<int>(provider.currentTab),
          child: screens[provider.currentTab],
        ),
      ),
      bottomNavigationBar: CleanBottomNav(
        currentIndex: provider.currentTab,
        onTabSelected: (index) => provider.setTab(index),
      ),
    );
  }
}

// ============================================================================
// 12. DASHBOARD SCREEN (PARALLAX SLIVERAPPBAR HEADER)
// ============================================================================
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openAddExpense(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AddExpenseBottomSheet(),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    final myBalance = provider.myNetBalance;
    final isOwed = myBalance > 0.009;
    final isOwes = myBalance < -0.009;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: const Center(
                    child: FaIcon(FontAwesomeIcons.bolt, size: 16, color: AppColors.primary),
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    BouncyButton(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PersonalExpensesScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const FaIcon(FontAwesomeIcons.piggyBank, size: 12, color: Color(0xFFEC4899)),
                            const SizedBox(width: 6),
                            Text(
                              'Personal',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFEC4899),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    BouncyButton(
                      onTap: () => _openSettings(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: Center(
                          child: FaIcon(FontAwesomeIcons.gear, size: 14, color: textColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'CAMPUS QUICKSPLIT LIVE',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Good day, Aarav 👋',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TODAY', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: mutedColor)),
                              const SizedBox(height: 4),
                              AnimatedRupeeCounter(
                                value: provider.todaySpending,
                                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: textColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('THIS MONTH', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: mutedColor)),
                              const SizedBox(height: 4),
                              AnimatedRupeeCounter(
                                value: provider.thisMonthSpending,
                                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: textColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isOwed ? AppColors.successGlow : (isOwes ? AppColors.dangerGlow : cardBg),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isOwed ? AppColors.success.withValues(alpha: 0.3) : (isOwes ? AppColors.danger.withValues(alpha: 0.3) : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOwed ? 'YOU GET' : (isOwes ? 'YOU OWE' : 'BALANCE'),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isOwed ? AppColors.success : (isOwes ? AppColors.danger : mutedColor),
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedRupeeCounter(
                                value: myBalance.abs(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isOwed ? AppColors.success : (isOwes ? AppColors.danger : textColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildQuickAction(context, FontAwesomeIcons.plus, 'Add Expense', AppColors.primary, () => _openAddExpense(context)),
                        _buildQuickAction(context, FontAwesomeIcons.message, 'From SMS', AppColors.accent, () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('SMS Parser: Parsed simulated canteen ₹160 UPI receipt')),
                          );
                        }),
                        _buildQuickAction(context, FontAwesomeIcons.fileImport, 'Import', AppColors.warning, () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Import: Ready for Splitwise CSV import')),
                          );
                        }),
                        _buildQuickAction(context, FontAwesomeIcons.repeat, 'Recurring', AppColors.teal, () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recurring: Monthly Flat Wi-Fi ₹899 scheduled')),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Active Squad Groups',
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      BouncyButton(
                        onTap: () => provider.setTab(1),
                        child: Text(
                          'See all (${provider.groups.length})',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 115,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: provider.groups.length,
                      itemBuilder: (ctx, i) {
                        final g = provider.groups[i];
                        return Container(
                          width: 170,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    g.name,
                                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
                                  ),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: g.color, shape: BoxShape.circle),
                                  ),
                                ],
                              ),
                              Text(
                                '${g.membersCount} members',
                                style: GoogleFonts.inter(fontSize: 11, color: mutedColor),
                              ),
                              Text(
                                g.status == 'owed'
                                    ? 'You get ${Formatters.formatRupee(g.amount)}'
                                    : (g.status == 'owe' ? 'You owe ${Formatters.formatRupee(g.amount)}' : 'Settled up'),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: g.status == 'owed' ? AppColors.success : (g.status == 'owe' ? AppColors.danger : mutedColor),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Activity',
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      BouncyButton(
                        onTap: () => provider.setTab(3),
                        child: Text(
                          'View all (${provider.expenses.length})',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (provider.expenses.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                      child: Text('No expenses recorded yet.', style: GoogleFonts.inter(fontSize: 13, color: mutedColor)),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: math.min(5, provider.expenses.length),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final exp = provider.expenses[i];
                        return Dismissible(
                          key: Key(exp.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const FaIcon(FontAwesomeIcons.trash, color: AppColors.danger, size: 18),
                          ),
                          onDismissed: (_) {
                            context.read<AppProvider>().deleteExpense(exp.id);
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Deleted "${exp.title}"'),
                                action: SnackBarAction(
                                  label: 'UNDO',
                                  textColor: AppColors.primary,
                                  onPressed: () => context.read<AppProvider>().undoDelete(),
                                ),
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                          child: ExpenseTile(expense: exp),
                        );
                      },
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, dynamic icon, String label, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;

    return BouncyButton(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(child: FaIcon(icon, size: 13, color: color)),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 13. GROUPS SCREEN
// ============================================================================
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  String _selectedFilter = 'All';

  static const List<String> _filters = ['All', 'Home', 'Trip', 'Couple', 'Personal', 'Flat'];

  void _openCreateGroupDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    String category = 'Home';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Create Squad Group', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: 'e.g. Manali Trip 2026, Flat 402'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: const ['Home', 'Trip', 'Couple', 'Personal', 'Flat']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => category = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  context.read<AppProvider>().addGroup(nameCtrl.text.trim(), category);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    final filteredGroups = provider.groups.where((g) {
      if (_selectedFilter == 'All') return true;
      return g.category.toLowerCase() == _selectedFilter.toLowerCase();
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Squad Groups',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: BouncyButton(
              onTap: () => _openCreateGroupDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Row(
                  children: [
                    FaIcon(FontAwesomeIcons.plus, size: 11, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'New Group',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              itemBuilder: (ctx, i) {
                final filter = _filters[i];
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BouncyButton(
                    onTap: () => setState(() => _selectedFilter = filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        filter,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : mutedColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: filteredGroups.length,
              itemBuilder: (ctx, i) {
                final g = filteredGroups[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: g.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: FaIcon(FontAwesomeIcons.users, size: 18, color: g.color),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(g.name, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
                                  Text('${g.membersCount} active squad members', style: GoogleFonts.inter(fontSize: 11, color: mutedColor)),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: g.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              g.category.toUpperCase(),
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: g.color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface.withValues(alpha: 0.5) : AppColors.lightSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Balance state:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: mutedColor)),
                                Text(
                                  g.status == 'owed'
                                      ? 'You get ${Formatters.formatRupee(g.amount)}'
                                      : (g.status == 'owe' ? 'You owe ${Formatters.formatRupee(g.amount)}' : 'All settled up'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: g.status == 'owed' ? AppColors.success : (g.status == 'owe' ? AppColors.danger : AppColors.success),
                                  ),
                                ),
                              ],
                            ),
                            if (g.details.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...g.details.map((d) => Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('• $d', style: GoogleFonts.inter(fontSize: 11, color: mutedColor)),
                              )),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 14. ANALYTICS SCREEN
// ============================================================================
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsTimeframe _timeframe = AnalyticsTimeframe.month;
  String _spendType = 'True Spending';

  static const List<String> _spendTypes = ['True Spending', 'Cash Out', 'Received', 'Paid'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    final now = DateTime.now();
    final List<Expense> periodExpenses = provider.expenses.where((e) {
      if (e.isSettlement) return false;
      if (_timeframe == AnalyticsTimeframe.week) {
        return e.date.isAfter(now.subtract(const Duration(days: 7)));
      } else if (_timeframe == AnalyticsTimeframe.month) {
        return e.date.isAfter(DateTime(now.year, now.month, 1));
      }
      return true;
    }).toList();

    double totalSpend = periodExpenses.fold(0.0, (s, e) => s + e.amount);

    final List<BarChartGroupData> barGroups = [];
    double maxDaily = 100.0;

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));

      final dayTotal = provider.expenses
          .where((e) => !e.isSettlement && e.date.isAfter(day) && e.date.isBefore(nextDay))
          .fold(0.0, (sum, e) => sum + e.amount);

      if (dayTotal > maxDaily) maxDaily = dayTotal;

      barGroups.add(
        BarChartGroupData(
          x: 6 - i,
          barRods: [
            BarChartRodData(
              toY: dayTotal,
              color: (i == 0) ? AppColors.primary : AppColors.accent.withValues(alpha: 0.8),
              width: 14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
        ),
      );
    }

    final Map<String, double> catMap = {};
    for (final exp in periodExpenses) {
      catMap[exp.category] = (catMap[exp.category] ?? 0.0) + exp.amount;
    }

    final pieSections = catMap.entries.map((entry) {
      final color = AppColors.categoryColors[entry.key] ?? AppColors.primary;
      return PieChartSectionData(
        value: entry.value,
        color: color,
        radius: 20,
        showTitle: false,
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Analytics', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _spendTypes.length,
                itemBuilder: (ctx, i) {
                  final type = _spendTypes[i];
                  final isSelected = _spendType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: BouncyButton(
                      onTap: () => setState(() => _spendType = type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          type,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : mutedColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.pillBg,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  _buildTfTab('This Week', AnalyticsTimeframe.week),
                  _buildTfTab('This Month', AnalyticsTimeframe.month),
                  _buildTfTab('All Time', AnalyticsTimeframe.allTime),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Daily Spend (Last 7 Days)', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                      Text('Max: ${Formatters.formatRupee(maxDaily)}', style: GoogleFonts.inter(fontSize: 11, color: mutedColor)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 160,
                    child: BarChart(
                      BarChartData(
                        maxY: maxDaily * 1.15,
                        barGroups: barGroups,
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (val, meta) {
                                final d = now.subtract(Duration(days: 6 - val.toInt()));
                                final label = val.toInt() == 6 ? 'Today' : DateFormat('E').format(d);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: mutedColor)),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Spending by Category', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                      Text(Formatters.formatRupee(totalSpend), style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (pieSections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No expenses recorded in this period', style: GoogleFonts.inter(fontSize: 12, color: mutedColor))),
                    )
                  else ...[
                    SizedBox(
                      height: 150,
                      child: PieChart(
                        PieChartData(
                          sections: pieSections,
                          centerSpaceRadius: 44,
                          sectionsSpace: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...catMap.entries.map((e) {
                      final pct = totalSpend > 0 ? (e.value / totalSpend * 100).toStringAsFixed(1) : '0';
                      final color = AppColors.categoryColors[e.key] ?? AppColors.primary;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(e.key, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
                            const Spacer(),
                            Text(Formatters.formatRupee(e.value), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: textColor)),
                            const SizedBox(width: 8),
                            Text('$pct%', style: GoogleFonts.inter(fontSize: 11, color: mutedColor)),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTfTab(String label, AnalyticsTimeframe tf) {
    final isSelected = _timeframe == tf;
    return Expanded(
      child: BouncyButton(
        onTap: () => setState(() => _timeframe = tf),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 15. BILLS SCREEN
// ============================================================================
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  String _search = '';
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    final categories = ['All', ...AppColors.categoryColors.keys];

    final filtered = provider.expenses.where((e) {
      final matchSearch = e.title.toLowerCase().contains(_search.toLowerCase()) ||
          e.note.toLowerCase().contains(_search.toLowerCase());
      final matchCat = _selectedCategory == 'All' || e.category == _selectedCategory;
      return matchSearch && matchCat;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Bills & History', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search expenses, chai, xerox...',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FaIcon(FontAwesomeIcons.magnifyingGlass, size: 14, color: mutedColor),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (ctx, i) {
                final cat = categories[i];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BouncyButton(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        cat,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : mutedColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text('No expenses matched your filter', style: GoogleFonts.inter(fontSize: 13, color: mutedColor)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final exp = filtered[i];
                      return Dismissible(
                        key: Key(exp.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const FaIcon(FontAwesomeIcons.trash, color: AppColors.danger, size: 18),
                        ),
                        onDismissed: (_) {
                          context.read<AppProvider>().deleteExpense(exp.id);
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Deleted "${exp.title}"'),
                              action: SnackBarAction(
                                label: 'UNDO',
                                textColor: AppColors.primary,
                                onPressed: () => context.read<AppProvider>().undoDelete(),
                              ),
                              duration: const Duration(seconds: 4),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        },
                        child: ExpenseTile(expense: exp),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 16. BALANCES SCREEN (WITH 3D TILT CARD & GRAPH REDUCTION BANNER)
// ============================================================================
class BalancesScreen extends StatefulWidget {
  const BalancesScreen({super.key});

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  int _subTabIndex = 0;

  void _launchUpi(String upiId, double amount, String name) async {
    final uri = Uri.parse('upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('UPI Intent simulated for ₹$amount to $upiId')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('UPI Intent simulated for ₹$amount to $upiId')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    final myBalance = provider.myNetBalance;
    final isOwed = myBalance > 0.009;
    final isOwes = myBalance < -0.009;

    final rawCount = DebtOptimizer.calculateRawUnoptimizedCount(provider.expenses);
    final optimizedCount = provider.pendingSettlements.length;
    final reductionPct = rawCount > 0 ? (((rawCount - optimizedCount) / rawCount) * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Balances & Settle', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BouncyButton(
                  onTap: () => setState(() => _subTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _subTabIndex == 0 ? AppColors.primary : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Balances',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _subTabIndex == 0 ? Colors.white : mutedColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BouncyButton(
                  onTap: () => setState(() => _subTabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _subTabIndex == 1 ? AppColors.primary : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Pool Money',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _subTabIndex == 1 ? Colors.white : mutedColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(100)),
                          child: const Text('NEW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_subTabIndex == 1) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: FaIcon(FontAwesomeIcons.piggyBank, size: 28, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Squad Pool Money Vault', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 6),
                    Text(
                      'Collect advance contributions for upcoming trips, cultural fest tickets, or shared hostel deposits.',
                      style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pool Money: Group vault initialized')),
                        );
                      },
                      child: const Text('Start Pool Collection'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Tilt3DCard(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    boxShadow: [
                      BoxShadow(
                        color: (isOwed ? AppColors.success : (isOwes ? AppColors.danger : AppColors.primary)).withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'OVERALL SQUAD BALANCE',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: mutedColor,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Row(
                              children: [
                                FaIcon(FontAwesomeIcons.handPointer, size: 9, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  '3D Tilt',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AnimatedRupeeCounter(
                        value: myBalance.abs(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: isOwed ? AppColors.success : (isOwes ? AppColors.danger : textColor),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isOwed
                            ? 'Squad friends owe you in total'
                            : (isOwes ? 'You owe friends in total' : 'All accounts are completely even!'),
                        style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: FaIcon(FontAwesomeIcons.diagramProject, size: 14, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Graph Optimization',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
                              ),
                              if (reductionPct > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    '-$reductionPct% transfers',
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '$rawCount raw directed debts → $optimizedCount greedy tree transfers',
                            style: GoogleFonts.inter(fontSize: 11, color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Optimal Settle Up (${provider.pendingSettlements.length} transfers)',
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: textColor),
              ),
              const SizedBox(height: 10),

              if (provider.pendingSettlements.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const FaIcon(FontAwesomeIcons.circleCheck, color: AppColors.success, size: 18),
                      const SizedBox(width: 10),
                      Text('No pending debt settlements!', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                    ],
                  ),
                )
              else
                ...provider.pendingSettlements.map((debt) {
                  final fromName = provider.getMemberName(debt.fromMemberId);
                  final toMember = provider.getMember(debt.toMemberId);
                  final toName = toMember?.name ?? 'Member';
                  final toUpi = toMember?.upiId ?? '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(fromName, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                                  const SizedBox(width: 6),
                                  FaIcon(FontAwesomeIcons.arrowRight, size: 10, color: mutedColor),
                                  const SizedBox(width: 6),
                                  Text(toName, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('UPI: $toUpi', style: GoogleFonts.inter(fontSize: 11, color: mutedColor)),
                            ],
                          ),
                        ),
                        Text(
                          Formatters.formatRupee(debt.amount),
                          style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.danger),
                        ),
                        const SizedBox(width: 10),
                        BouncyButton(
                          onTap: () {
                            showUpiQrDialog(
                              context,
                              receiverName: toName,
                              upiId: toUpi,
                              amount: debt.amount,
                              onSettled: () {
                                _launchUpi(toUpi, debt.amount, toName);
                                provider.settleDebt(debt.fromMemberId, debt.toMemberId, debt.amount);
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Row(
                              children: [
                                FaIcon(FontAwesomeIcons.qrcode, size: 11, color: Colors.white),
                                SizedBox(width: 5),
                                Text(
                                  'Settle',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 17. SETTINGS SHEET
// ============================================================================
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final _nameCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: mutedColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Settings & Squad', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dark Mode', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
              Switch(
                value: provider.themeMode == ThemeMode.dark,
                activeThumbColor: AppColors.primary,
                onChanged: (_) => provider.toggleTheme(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text('ADD SQUAD MEMBER', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: mutedColor, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(hintText: 'Name (e.g. Yash)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _upiCtrl,
                  decoration: const InputDecoration(hintText: 'UPI ID (yash@upi)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_nameCtrl.text.trim().isNotEmpty) {
                  provider.addMember(_nameCtrl.text.trim(), _upiCtrl.text.trim());
                  _nameCtrl.clear();
                  _upiCtrl.clear();
                }
              },
              child: const Text('Add Member'),
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                provider.resetAllData();
                Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Reset All Campus Expenses'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ============================================================================
// 18. ADD EXPENSE BOTTOM SHEET
// ============================================================================
class AddExpenseBottomSheet extends StatefulWidget {
  const AddExpenseBottomSheet({super.key});

  @override
  State<AddExpenseBottomSheet> createState() => _AddExpenseBottomSheetState();
}

class _AddExpenseBottomSheetState extends State<AddExpenseBottomSheet> {
  final _amountCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _selectedCategory = 'Canteen';
  bool _isMultiPayer = false;
  String _singlePayerId = '1';
  int _activeBillTab = 0;
  int _selectedBrandIndex = 0;
  SplitMode _splitMode = SplitMode.equal;

  final Set<String> _selectedSplitters = {};
  final Map<String, TextEditingController> _paidCtrls = {};
  final Map<String, TextEditingController> _exactCtrls = {};
  final Map<String, TextEditingController> _percentCtrls = {};

  static const List<Map<String, dynamic>> _payBrands = [
    {'name': 'PhonePe', 'color': Color(0xFF5F259F), 'letter': 'P'},
    {'name': 'GPay', 'color': Color(0xFF4285F4), 'letter': 'G'},
    {'name': 'Paytm', 'color': Color(0xFF00BAF2), 'letter': 'P'},
    {'name': 'Zomato', 'color': Color(0xFFE23744), 'letter': 'Z'},
    {'name': 'Swiggy', 'color': Color(0xFFFC8019), 'letter': 'S'},
    {'name': 'Zepto', 'color': Color(0xFF7B2CBF), 'letter': 'Z'},
    {'name': 'Blinkit', 'color': Color(0xFFF8CB46), 'letter': 'B'},
  ];

  @override
  void initState() {
    super.initState();
    final members = context.read<AppProvider>().members;
    for (var m in members) {
      _selectedSplitters.add(m.id);
      _paidCtrls[m.id] = TextEditingController();
      _exactCtrls[m.id] = TextEditingController();
      _percentCtrls[m.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    for (var c in _paidCtrls.values) { c.dispose(); }
    for (var c in _exactCtrls.values) { c.dispose(); }
    for (var c in _percentCtrls.values) { c.dispose(); }
    super.dispose();
  }

  void _recalculateAutoSplits() {
    final rawAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (rawAmount <= 0 || _selectedSplitters.isEmpty) return;

    if (_splitMode == SplitMode.equal) {
      final splits = SplitEngine.calculateEqualSplits(
        totalAmount: rawAmount,
        memberIds: _selectedSplitters.toList(),
      );
      splits.forEach((id, amt) {
        _exactCtrls[id]?.text = amt.toStringAsFixed(2);
      });
    } else if (_splitMode == SplitMode.percentage) {
      final pct = 100.0 / _selectedSplitters.length;
      for (var id in _selectedSplitters) {
        _percentCtrls[id]?.text = pct.toStringAsFixed(1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;
    const splitLabels = ['Equally', 'Unequally', 'By %'];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: mutedColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CustomPaint(
                      painter: DashedBorderPainter(
                        color: AppColors.primary,
                        radius: 12,
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(
                          child: FaIcon(FontAwesomeIcons.plus, size: 12, color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 38,
                      width: 100,
                      child: Stack(
                        children: List.generate(
                          math.min(4, provider.members.length),
                          (i) => Positioned(
                            left: i * 22.0,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: provider.members[i].avatarColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: cardBg, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  provider.members[i].name.isNotEmpty ? provider.members[i].name[0].toUpperCase() : 'M',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    BouncyButton(
                      onTap: () => setState(() => _activeBillTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _activeBillTab == 0 ? AppColors.warning : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'Bill 1',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _activeBillTab == 0 ? AppColors.neutralBlack : mutedColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '+ Add bill',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Text(
                    '₹',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: mutedColor.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (_) => _recalculateAutoSplits(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _payBrands.length,
                itemBuilder: (ctx, i) {
                  final brand = _payBrands[i];
                  final isSelected = _selectedBrandIndex == i;
                  return BouncyButton(
                    onTap: () => setState(() => _selectedBrandIndex = i),
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: brand['color'] as Color,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
                        boxShadow: [
                          BoxShadow(
                            color: (brand['color'] as Color).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          brand['letter'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Expense Title',
                hintText: 'e.g. Canteen Treat, Auto to Campus',
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (Optional)',
                hintText: 'e.g. Extra juice included',
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'CATEGORY',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: mutedColor, letterSpacing: 0.8),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: AppColors.categoryColors.keys.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  final catColor = AppColors.categoryColors[cat] ?? AppColors.primary;
                  final catIcon = AppColors.categoryFaIcons[cat] ?? FontAwesomeIcons.tags;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: BouncyButton(
                      onTap: () => setState(() => _selectedCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : (isDark ? AppColors.darkSurface : AppColors.pillBg),
                          borderRadius: BorderRadius.circular(100),
                          border: isSelected ? null : Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(
                              catIcon,
                              size: 14,
                              color: isSelected ? Colors.white : catColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              cat,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : (isDark ? AppColors.textMuted : AppColors.neutralGray),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PAID BY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: mutedColor, letterSpacing: 0.8)),
                Row(
                  children: [
                    Text('Multiple Payers', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
                    Switch(
                      value: _isMultiPayer,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) => setState(() => _isMultiPayer = val),
                    ),
                  ],
                ),
              ],
            ),
            if (!_isMultiPayer)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DropdownButton<String>(
                  value: _singlePayerId,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: provider.members.map((m) {
                    return DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        m.name,
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: textColor),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _singlePayerId = v);
                  },
                ),
              )
            else
              Column(
                children: provider.members.map((m) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(m.name,
                                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor))),
                        SizedBox(
                          width: 100,
                          height: 40,
                          child: TextField(
                            controller: _paidCtrls[m.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              prefixText: '₹ ',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: List.generate(3, (i) {
                  final mode = SplitMode.values[i];
                  final isSelected = _splitMode == mode;
                  return Expanded(
                    child: BouncyButton(
                      onTap: () {
                        setState(() => _splitMode = mode);
                        _recalculateAutoSplits();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Center(
                          child: Text(
                            splitLabels[i],
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : mutedColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'SPLIT AMONG (${_selectedSplitters.length} selected)',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: mutedColor, letterSpacing: 0.8),
            ),
            const SizedBox(height: 12),

            Column(
              children: provider.members.map((m) {
                final isSelected = _selectedSplitters.contains(m.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedSplitters.add(m.id);
                            } else if (_selectedSplitters.length > 1) {
                              _selectedSplitters.remove(m.id);
                            }
                          });
                          _recalculateAutoSplits();
                        },
                      ),
                      Expanded(
                        child: Text(
                          m.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (isSelected && _splitMode == SplitMode.exact)
                        SizedBox(
                          width: 90,
                          height: 38,
                          child: TextField(
                            controller: _exactCtrls[m.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              prefixText: '₹ ',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                          ),
                        ),
                      if (isSelected && _splitMode == SplitMode.percentage)
                        SizedBox(
                          width: 80,
                          height: 38,
                          child: TextField(
                            controller: _percentCtrls[m.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              suffixText: '%',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(FontAwesomeIcons.camera, size: 12, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Add image',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(FontAwesomeIcons.qrcode, size: 12, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Scan bill',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : const Color(0xFFE0E7FF),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(FontAwesomeIcons.calendar, size: 12, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('dd MMM').format(DateTime.now()),
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: BouncyButton(
                onTap: _saveExpense,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.neutralBlack,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Submit expense',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveExpense() {
    final title = _titleCtrl.text.trim();
    final rawAmount = double.tryParse(_amountCtrl.text.trim());

    if (title.isEmpty ||
        rawAmount == null ||
        !rawAmount.isFinite ||
        rawAmount.isNaN ||
        rawAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid title and finite numeric amount > ₹0')),
      );
      return;
    }

    if (_selectedSplitters.isEmpty ||
        _selectedSplitters.length > context.read<AppProvider>().members.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid participant selection count')),
      );
      return;
    }

    final Map<String, double> finalPaidBy = {};
    if (!_isMultiPayer) {
      finalPaidBy[_singlePayerId] = rawAmount;
    } else {
      double sumPaid = 0.0;
      for (var id in context.read<AppProvider>().members.map((m) => m.id)) {
        final val = double.tryParse(_paidCtrls[id]?.text.trim() ?? '0') ?? 0.0;
        if (!val.isFinite || val.isNaN || val < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid numerical payer input')),
          );
          return;
        }
        if (val > 0) {
          finalPaidBy[id] = val;
          sumPaid += val;
        }
      }
      if ((sumPaid - rawAmount).abs() > 0.009) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Multi-payer sum (₹$sumPaid) must equal total expense (₹$rawAmount)')),
        );
        return;
      }
    }

    final Map<String, double> finalSplits = {};

    if (_splitMode == SplitMode.equal) {
      finalSplits.addAll(SplitEngine.calculateEqualSplits(
        totalAmount: rawAmount,
        memberIds: _selectedSplitters.toList(),
      ));
    } else if (_splitMode == SplitMode.exact) {
      double sumExact = 0.0;
      for (final id in _selectedSplitters) {
        final val = double.tryParse(_exactCtrls[id]?.text.trim() ?? '0') ?? 0.0;
        if (!val.isFinite || val.isNaN || val < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exact splits cannot be negative or NaN')),
          );
          return;
        }
        finalSplits[id] = val;
        sumExact += val;
      }
      if ((sumExact - rawAmount).abs() > 0.009) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Sum of exact splits (₹$sumExact) must equal total amount (₹$rawAmount) exactly')),
        );
        return;
      }
    } else {
      double sumPct = 0.0;
      for (final id in _selectedSplitters) {
        final pct = double.tryParse(_percentCtrls[id]?.text.trim() ?? '0') ?? 0.0;
        if (!pct.isFinite || pct.isNaN || pct < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Percentages cannot be negative or NaN')),
          );
          return;
        }
        sumPct += pct;
        finalSplits[id] = (rawAmount * pct) / 100.0;
      }
      if ((sumPct - 100.0).abs() > 0.009) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Total percentage sum (${sumPct.toStringAsFixed(2)}%) must equal 100.00% exactly')),
        );
        return;
      }
    }

    final expense = Expense(
      id: const Uuid().v4(),
      title: title,
      amount: rawAmount,
      category: _selectedCategory,
      date: DateTime.now(),
      paidBy: finalPaidBy,
      splitMode: _splitMode,
      splits: finalSplits,
      note: _noteCtrl.text.trim(),
    );

    context.read<AppProvider>().addExpense(expense);
    Navigator.pop(context);
  }
}

// ============================================================================
// 7H. EXPENSE TILE
// ============================================================================
class ExpenseTile extends StatelessWidget {
  final Expense expense;

  const ExpenseTile({super.key, required this.expense});

  void _showExpenseDetails(BuildContext context) {
    final provider = context.read<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: mutedColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                buildCategoryIcon(expense.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      Text(
                        Formatters.formatTimestampWithRelative(expense.date),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  Formatters.formatRupee(expense.amount),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            if (expense.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Note: ${expense.note}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textColor,
                      fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            const SizedBox(height: 12),
            Text(
              'SPLIT ALLOCATION (${expense.splitMode.name.toUpperCase()} MODE)',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: mutedColor,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            ...expense.splits.entries.map((entry) {
              final memberName = provider.getMemberName(entry.key);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      memberName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'Owes ${Formatters.formatRupee(entry.value)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;

    final payerNames = expense.paidBy.keys
        .map((id) => provider.getMemberName(id))
        .join(', ');

    return BouncyButton(
      onTap: () => _showExpenseDetails(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            buildCategoryIcon(expense.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Paid by $payerNames • ${Formatters.formatTimestampWithRelative(expense.date)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: mutedColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              Formatters.formatRupee(expense.amount),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: expense.isSettlement ? AppColors.success : textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7I. PERSONAL EXPENSES SCREEN
// ============================================================================
class PersonalExpensesScreen extends StatelessWidget {
  const PersonalExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.neutralBlack;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.neutralGray;
    final scaffoldBg = isDark ? AppColors.darkBg : AppColors.lightBg;

    const personalItems = [
      {'name': 'Extra', 'amount': 4900.0, 'color': Color(0xFF8B5CF6), 'highlight': false},
      {'name': 'Shopping', 'amount': 2245.0, 'color': Color(0xFFFF8C42), 'highlight': false},
      {'name': 'Groceries', 'amount': 2000.0, 'color': AppColors.success, 'highlight': true},
      {'name': 'Food', 'amount': 340.0, 'color': Color(0xFFEF4444), 'highlight': false},
    ];

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: scaffoldBg,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: BouncyButton(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Center(
                  child: FaIcon(FontAwesomeIcons.arrowLeft, size: 14, color: textColor),
                ),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Center(
                  child: FaIcon(FontAwesomeIcons.bell, size: 14, color: textColor),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFEC4899).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: FaIcon(FontAwesomeIcons.piggyBank, color: Color(0xFFEC4899), size: 44),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'My Personal Expenditure',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Primary',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8B5CF6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPersonalAction(context, FontAwesomeIcons.fileArrowDown, 'Export', AppColors.primary),
                const SizedBox(width: 24),
                _buildPersonalAction(context, FontAwesomeIcons.repeat, 'Recurring', const Color(0xFF14B8A6)),
                const SizedBox(width: 24),
                _buildPersonalAction(context, FontAwesomeIcons.sliders, 'Settings', const Color(0xFFFF8C42)),
              ],
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.pillBg,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Text(
                          'Expense',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: mutedColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Center(
                        child: Text(
                          'Summary',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Category Wise',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.pillBg,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Total Spending',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: mutedColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Category-wise Summary',
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : AppColors.pillBg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          children: [
                            Text('Aug 2026', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
                            const SizedBox(width: 4),
                            FaIcon(FontAwesomeIcons.filter, size: 9, color: mutedColor),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            centerSpaceRadius: 60,
                            sectionsSpace: 3,
                            startDegreeOffset: -90,
                            sections: [
                              PieChartSectionData(value: 4900, color: const Color(0xFF8B5CF6), radius: 24, title: ''),
                              PieChartSectionData(value: 2245, color: const Color(0xFFFF8C42), radius: 24, title: ''),
                              PieChartSectionData(value: 2000, color: AppColors.success, radius: 28, title: ''),
                              PieChartSectionData(value: 340, color: const Color(0xFFEF4444), radius: 24, title: ''),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '51.6%',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'Extra',
                              style: GoogleFonts.inter(fontSize: 11, color: mutedColor, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  ...personalItems.map((item) {
                    final isHighlighted = item['highlight'] as bool;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? AppColors.success.withValues(alpha: isDark ? 0.15 : 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isHighlighted ? Border.all(color: AppColors.success.withValues(alpha: 0.3)) : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: item['color'] as Color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            item['name'] as String,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                          ),
                          const Spacer(),
                          Text(
                            Formatters.formatRupee(item['amount'] as double),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isHighlighted ? AppColors.success : textColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalAction(BuildContext context, dynamic icon, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: FaIcon(icon, color: color, size: 18),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textMuted : AppColors.neutralGray,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 19. ENTRYPOINT
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await Hive.initFlutter();
  final appProvider = AppProvider();
  await appProvider.init();

  runApp(
    ChangeNotifierProvider.value(
      value: appProvider,
      child: const CampusQuickSplitApp(),
    ),
  );
}

class CampusQuickSplitApp extends StatelessWidget {
  const CampusQuickSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return MaterialApp(
      title: 'Campus QuickSplit',
      debugShowCheckedModeBanner: false,
      themeMode: provider.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.lightBg,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.success,
          surface: AppColors.lightCard,
          onSurface: AppColors.lightText,
          error: AppColors.danger,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.lightBg,
          elevation: 0,
          foregroundColor: AppColors.lightText,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.lightCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          labelStyle: GoogleFonts.inter(color: AppColors.neutralGray),
          hintStyle: GoogleFonts.inter(color: AppColors.neutralGray),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.lightBorder),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.success,
          surface: AppColors.darkCard,
          onSurface: Colors.white,
          error: AppColors.danger,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBg,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          labelStyle: GoogleFonts.inter(color: AppColors.textMuted),
          hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.darkBorder),
      ),
      home: const SplashOrMainWrapper(),
    );
  }
}

class SplashOrMainWrapper extends StatefulWidget {
  const SplashOrMainWrapper({super.key});

  @override
  State<SplashOrMainWrapper> createState() => _SplashOrMainWrapperState();
}

class _SplashOrMainWrapperState extends State<SplashOrMainWrapper> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onFinish: () {
          if (mounted) setState(() => _showSplash = false);
        },
      );
    }
    return const MainShellScreen();
  }
}