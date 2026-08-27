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

// ============================================================================
// 1. DESIGN TOKENS
// ============================================================================
class AppColors {
  static const Color darkBg = Color(0xFF0A0E21);
  static const Color darkCard = Color(0xFF1E2235);
  static const Color darkBorder = Color(0xFF2A2F4A);
  static const Color darkSurface = Color(0xFF12162A);

  static const Color lightBg = Color(0xFFF8F9FF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightSurface = Color(0xFFEEF2F6);
  static const Color lightText = Color(0xFF1A1E30);

  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF4B44CC);
  static const Color secondary = Color(0xFFFF6584);
  static const Color success = Color(0xFF00C896);
  static const Color warning = Color(0xFFFFB84C);
  static const Color textMuted = Color(0xFF9CA3AF);

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

  static const Map<String, String> categoryIcons = {
    'Canteen': '🍔',
    'Chai & Snacks': '☕',
    'Auto': '🛺',
    'Xerox': '📄',
    'Mess': '🍛',
    'Subscriptions': '🎬',
    'Groceries': '🛒',
    'Other': '🏷️',
  };
}

// ============================================================================
// 2. DATA MODELS
// ============================================================================
enum SplitMode { equal, exact, percentage }
enum AnalyticsTimeframe { week, month, allTime }

class Member {
  final String id;
  final String name;
  final String avatarColor;
  final String upiId;

  Member({
    required this.id,
    required this.name,
    required this.avatarColor,
    this.upiId = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatarColor': avatarColor,
        'upiId': upiId,
      };

  factory Member.fromMap(Map<String, dynamic> map) => Member(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        avatarColor: map['avatarColor'] ?? '#6C63FF',
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

  factory Expense.fromMap(Map<String, dynamic> map) {
    bool parseBool(dynamic val) {
      if (val == null) return false;
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      return false;
    }

    return Expense(
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
      isSettlement: parseBool(map['isSettlement']),
    );
  }
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

// ============================================================================
// 3. MATHEMATICAL ENGINE & DEBT OPTIMIZER
// ============================================================================
class SplitEngine {
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
  static Map<String, double> computeNetBalances({
    required List<Member> members,
    required List<Expense> expenses,
    required List<SettlementRecord> settlements,
  }) {
    final Map<String, double> balances = {for (var m in members) m.id: 0.0};

    for (final exp in expenses) {
      if (exp.isSettlement) continue;
      exp.paidBy.forEach((payerId, paidAmount) {
        balances[payerId] = (balances[payerId] ?? 0.0) + paidAmount;
      });
      exp.splits.forEach((borrowerId, owedAmount) {
        balances[borrowerId] = (balances[borrowerId] ?? 0.0) - owedAmount;
      });
    }

    for (final s in settlements) {
      balances[s.fromMemberId] = (balances[s.fromMemberId] ?? 0.0) + s.amount;
      balances[s.toMemberId] = (balances[s.toMemberId] ?? 0.0) - s.amount;
    }

    return balances;
  }

  static List<SimplifiedDebt> computeSimplifiedDebts({
    required List<Member> members,
    required List<Expense> expenses,
    required List<SettlementRecord> settlements,
  }) {
    if (members.isEmpty) return [];

    final balances = computeNetBalances(
      members: members,
      expenses: expenses,
      settlements: settlements,
    );

    final List<MapEntry<String, double>> debtors = [];
    final List<MapEntry<String, double>> creditors = [];

    balances.forEach((memberId, net) {
      if (net < -0.009) debtors.add(MapEntry(memberId, net));
      if (net > 0.009) creditors.add(MapEntry(memberId, net));
    });

    debtors.sort((a, b) => a.value.compareTo(b.value));
    creditors.sort((a, b) => b.value.compareTo(a.value));

    final List<SimplifiedDebt> result = [];
    int dIdx = 0;
    int cIdx = 0;

    final Map<String, double> tempBalances = Map.from(balances);

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

    static int calculateRawUnoptimizedCount(List<Expense> expenses) {
    final Set<String> rawTransfers = {};
    for (var exp in expenses) {
      if (exp.isSettlement) continue;

      // Only non-payers create raw outbound debts to payers
      final payerIds = exp.paidBy.entries
          .where((e) => e.value > 0)
          .map((e) => e.key)
          .toSet();

      for (final payerId in payerIds) {
        exp.splits.forEach((borrowerId, owedAmt) {
          if (!payerIds.contains(borrowerId) && owedAmt > 0) {
            rawTransfers.add('${exp.id}_${borrowerId}_to_$payerId');
          }
        });
      }
    }
    return rawTransfers.length;
  }
}

// ============================================================================
// 4. PROVIDER STATE CONTROLLER
// ============================================================================
class AppProvider extends ChangeNotifier {
  static const String boxName = 'campus_quicksplit_box';
  Box? _box;

  ThemeMode _themeMode = ThemeMode.dark;
  int _currentTabIndex = 0;
  AnalyticsTimeframe _analyticsTimeframe = AnalyticsTimeframe.month;

  List<Member> _members = [
    Member(id: '1', name: 'Aarav (You)', avatarColor: '#6C63FF', upiId: 'aarav@okaxis'),
    Member(id: '2', name: 'Rohan', avatarColor: '#00C896', upiId: 'rohan@oksbi'),
    Member(id: '3', name: 'Priya', avatarColor: '#FF6584', upiId: 'priya@okicici'),
    Member(id: '4', name: 'Kabir', avatarColor: '#FFB84C', upiId: 'kabir@paytm'),
  ];
  List<Expense> _expenses = [];
  List<SettlementRecord> _settlements = [];
  Expense? _recentlyDeletedExpense;

  AppProvider() {
    _seedDefaultExpenses();
  }

  void _seedDefaultExpenses() {
    final now = DateTime.now();
    _expenses = [
      Expense(
        id: const Uuid().v4(),
        title: 'Campus Canteen Thali & Juice',
        amount: 480.0,
        category: 'Canteen',
        date: now.subtract(const Duration(hours: 3)),
        paidBy: {'1': 480.0},
        splitMode: SplitMode.equal,
        splits: SplitEngine.calculateEqualSplits(
            totalAmount: 480.0, memberIds: ['1', '2', '3', '4']),
        note: 'Post mid-sem lunch treat',
      ),
      Expense(
        id: const Uuid().v4(),
        title: 'Shared Auto to Metro',
        amount: 120.0,
        category: 'Auto',
        date: now.subtract(const Duration(days: 1)),
        paidBy: {'2': 120.0},
        splitMode: SplitMode.equal,
        splits: SplitEngine.calculateEqualSplits(
            totalAmount: 120.0, memberIds: ['1', '2', '4']),
        note: 'Evening commute',
      ),
      Expense(
        id: const Uuid().v4(),
        title: 'Lab Manual Xerox & Binding',
        amount: 250.0,
        category: 'Xerox',
        date: now.subtract(const Duration(days: 2)),
        paidBy: {'3': 250.0},
        splitMode: SplitMode.equal,
        splits: SplitEngine.calculateEqualSplits(
            totalAmount: 250.0, memberIds: ['1', '2', '3', '4']),
      ),
    ];
    _sortExpenses();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  int get currentTabIndex => _currentTabIndex;
  AnalyticsTimeframe get analyticsTimeframe => _analyticsTimeframe;
  List<Member> get members => List.unmodifiable(_members);
  List<Expense> get expenses => List.unmodifiable(_expenses);
  List<SettlementRecord> get settlements => List.unmodifiable(_settlements);

  Future<void> init() async {
    _box = await Hive.openBox(boxName);
    _loadFromStorage();
  }

  void _loadFromStorage() {
    if (_box == null) return;

    final isDarkMode = _box!.get('is_dark_mode', defaultValue: true);
    _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;

    final membersRaw = _box!.get('members');
    if (membersRaw != null) {
      _members = (jsonDecode(membersRaw) as List)
          .map((e) => Member.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    final expensesRaw = _box!.get('expenses');
    if (expensesRaw != null) {
      _expenses = (jsonDecode(expensesRaw) as List)
          .map((e) => Expense.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      _sortExpenses();
    }

    final settlementsRaw = _box!.get('settlements');
    if (settlementsRaw != null) {
      _settlements = (jsonDecode(settlementsRaw) as List)
          .map((e) => SettlementRecord.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    notifyListeners();
  }

  void _sortExpenses() {
    _expenses.sort((a, b) => b.date.compareTo(a.date));
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _box?.put('is_dark_mode', _themeMode == ThemeMode.dark);
    notifyListeners();
  }

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  void setAnalyticsTimeframe(AnalyticsTimeframe tf) {
    _analyticsTimeframe = tf;
    notifyListeners();
  }

  void _saveMembers() {
    _box?.put('members', jsonEncode(_members.map((m) => m.toMap()).toList()));
  }

  void _saveExpenses() {
    _box?.put('expenses', jsonEncode(_expenses.map((e) => e.toMap()).toList()));
  }

  void _saveSettlements() {
    _box?.put('settlements', jsonEncode(_settlements.map((s) => s.toMap()).toList()));
  }

  void addMember(String name, String upiId) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    final colors = ['#6C63FF', '#00C896', '#FF6584', '#FFB84C', '#38BDF8', '#A78BFA'];
    final randomColor = colors[_members.length % colors.length];
    final member = Member(
      id: const Uuid().v4(),
      name: trimmedName,
      avatarColor: randomColor,
      upiId: upiId.trim(),
    );
    _members.add(member);
    _saveMembers();
    notifyListeners();
  }

  void addExpense(Expense expense) {
    _expenses.add(expense);
    _sortExpenses();
    _saveExpenses();
    notifyListeners();
  }

  void deleteExpense(String id) {
    final index = _expenses.indexWhere((e) => e.id == id);
    if (index != -1) {
      _recentlyDeletedExpense = _expenses[index];
      _expenses.removeAt(index);
      _saveExpenses();
      notifyListeners();
    }
  }

  void undoDeleteExpense() {
    if (_recentlyDeletedExpense != null) {
      _expenses.add(_recentlyDeletedExpense!);
      _recentlyDeletedExpense = null;
      _sortExpenses();
      _saveExpenses();
      notifyListeners();
    }
  }

  void markDebtSettled(String fromId, String toId, double amount) {
    final settlementRecord = SettlementRecord(
      id: const Uuid().v4(),
      fromMemberId: fromId,
      toMemberId: toId,
      amount: amount,
      date: DateTime.now(),
    );
    _settlements.add(settlementRecord);
    _saveSettlements();

    final fromName = getMemberName(fromId);
    final toName = getMemberName(toId);

    final settlementExpense = Expense(
      id: const Uuid().v4(),
      title: 'Settled: $fromName ➔ $toName',
      amount: amount,
      category: 'Other',
      date: DateTime.now(),
      paidBy: {fromId: amount},
      splitMode: SplitMode.exact,
      splits: {toId: amount},
      note: 'Marked as settled via UPI',
      isSettlement: true,
    );

    _expenses.add(settlementExpense);
    _sortExpenses();
    _saveExpenses();

    notifyListeners();
  }

  void resetAllData() {
    _expenses.clear();
    _settlements.clear();
    _saveExpenses();
    _saveSettlements();
    notifyListeners();
  }

  String getMemberName(String id) {
    final member = _members.firstWhere(
      (m) => m.id == id,
      orElse: () => Member(id: id, name: 'Squad Member', avatarColor: '#6C63FF'),
    );
    return member.name;
  }

  Member? getMember(String id) {
    try {
      return _members.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  double get totalGroupSpend => _expenses
      .where((e) => !e.isSettlement)
      .fold(0.0, (sum, item) => sum + item.amount);

  Map<String, double> get memberNetBalances => DebtOptimizer.computeNetBalances(
        members: _members,
        expenses: _expenses,
        settlements: _settlements,
      );

  double get myNetBalance => memberNetBalances['1'] ?? 0.0;

  List<SimplifiedDebt> get pendingSettlements {
    return DebtOptimizer.computeSimplifiedDebts(
      members: _members,
      expenses: _expenses,
      settlements: _settlements,
    );
  }

  List<Expense> get filteredAnalyticsExpenses {
    final now = DateTime.now();
    return _expenses.where((exp) {
      if (exp.isSettlement || exp.date.isAfter(now)) return false;

      if (_analyticsTimeframe == AnalyticsTimeframe.week) {
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        return exp.date.isAfter(startOfWeekDay) || exp.date.isAtSameMomentAs(startOfWeekDay);
      } else if (_analyticsTimeframe == AnalyticsTimeframe.month) {
        final startOfMonth = DateTime(now.year, now.month, 1);
        return exp.date.isAfter(startOfMonth) || exp.date.isAtSameMomentAs(startOfMonth);
      }
      return true;
    }).toList();
  }

  Map<String, double> get categorySpendMap {
    final map = <String, double>{};
    for (final exp in filteredAnalyticsExpenses) {
      map[exp.category] = (map[exp.category] ?? 0.0) + exp.amount;
    }
    return map;
  }
}

// ============================================================================
// 5. HELPER FORMATTERS
// ============================================================================
class Formatters {
  static final NumberFormat currencyFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static String formatRupee(double amount) {
    return currencyFormatter.format(amount);
  }

  static String formatTimestampWithRelative(DateTime dt) {
    final exact = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    final now = DateTime.now();
    final diff = now.difference(dt);

    String relative = '';
    if (diff.inMinutes < 60) {
      relative = '${math.max(1, diff.inMinutes)}m ago';
    } else if (diff.inHours < 24) {
      relative = '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      relative = 'Yesterday';
    } else {
      relative = '${diff.inDays}d ago';
    }

    return '$exact ($relative)';
  }

  static Color parseHexColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

// ============================================================================
// 6. CUSTOM WIDGETS
// ============================================================================

class BouncyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const BouncyButton({super.key, required this.child, required this.onTap});

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class AnimatedRupeeCounter extends StatelessWidget {
  final double value;
  final TextStyle style;

  const AnimatedRupeeCounter({super.key, required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: value),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutExpo,
      builder: (context, animatedValue, child) {
        return Text(
          Formatters.formatRupee(animatedValue),
          style: style,
        );
      },
    );
  }
}

class SymmetricalNotchedBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const SymmetricalNotchedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(context, 0, Icons.dashboard_rounded, 'Overview'),
              _buildNavItem(context, 1, Icons.receipt_long_rounded, 'Activity'),
              const SizedBox(width: 48),
              _buildNavItem(context, 2, Icons.pie_chart_rounded, 'Analytics'),
              _buildNavItem(context, 3, Icons.settings_rounded, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, IconData icon, String label) {
    final isSelected = currentIndex == index;
    final activeColor = AppColors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textInactive = isDark ? AppColors.textMuted : const Color(0xFF64748B);

    return BouncyButton(
      onTap: () => onTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? activeColor : textInactive,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : textInactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. SCREENS
// ============================================================================

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _typedTitle = '';
  final String _fullTitle = 'Campus QuickSplit';
  int _charIndex = 0;
  bool _showTagline = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startTypewriter();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _startTypewriter() async {
    while (_charIndex < _fullTitle.length) {
      await Future.delayed(const Duration(milliseconds: 55));
      if (_disposed || !mounted) return;
      setState(() {
        _charIndex++;
        _typedTitle = _fullTitle.substring(0, _charIndex);
      });
    }

    await Future.delayed(const Duration(milliseconds: 180));
    if (_disposed || !mounted) return;
    setState(() => _showTagline = true);

    await Future.delayed(const Duration(milliseconds: 900));
    if (_disposed || !mounted) return;
    widget.onFinish();
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
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.5),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Center(
                child: Text('⚡', style: TextStyle(fontSize: 40)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _typedTitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              opacity: _showTagline ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: Text(
                'Split Smart. Settle Fast.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainShellScreen extends StatelessWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    final screens = const [
      DashboardScreen(),
      ActivityScreen(),
      AnalyticsScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: screens[provider.currentTabIndex],
      ),
      bottomNavigationBar: SymmetricalNotchedBottomNav(
        currentIndex: provider.currentTabIndex,
        onTap: (index) => provider.setTabIndex(index),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: BouncyButton(
        onTap: () => _openAddExpenseModal(context),
        child: Container(
          height: 58,
          width: 58,
          margin: const EdgeInsets.only(top: 24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  void _openAddExpenseModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AddExpenseBottomSheet(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    final rawDebtCount = DebtOptimizer.calculateRawUnoptimizedCount(provider.expenses);
    final optimizedDebtCount = provider.pendingSettlements.length;
    final memberBalances = provider.memberNetBalances;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Campus QuickSplit',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Hostel & Squad Expenses',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? Colors.amber : AppColors.primary,
            ),
            onPressed: () => provider.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'YOUR NET BALANCE',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Group Total: ${Formatters.formatRupee(provider.totalGroupSpend)}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AnimatedRupeeCounter(
                      value: provider.myNetBalance,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOU ARE OWED',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                AnimatedRupeeCounter(
                                  value: math.max(0.0, provider.myNetBalance),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 28,
                            width: 1,
                            color: Colors.white.withOpacity(0.15),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOU OWE',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                AnimatedRupeeCounter(
                                  value: math.max(0.0, -provider.myNetBalance),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_tree_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Minimum Transaction Path Engine',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'O(N log N) Graph',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Raw Unoptimized: $rawDebtCount transfers',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                      Text(
                        'Optimized: $optimizedDebtCount transfers',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'All Squad Balances',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${provider.members.length} members',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: provider.members.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                itemBuilder: (ctx, i) {
                  final member = provider.members[i];
                  final balance = memberBalances[member.id] ?? 0.0;
                  final isOwed = balance > 0.009;
                  final isDebtor = balance < -0.009;

                  final statusColor = isOwed
                      ? AppColors.success
                      : (isDebtor ? AppColors.secondary : AppColors.textMuted);

                  final statusText = isOwed
                      ? 'is owed ${Formatters.formatRupee(balance)}'
                      : (isDebtor
                          ? 'owes ${Formatters.formatRupee(-balance)}'
                          : 'Settled (₹0.00)');

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Formatters.parseHexColor(member.avatarColor),
                      child: Text(
                        member.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      member.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    trailing: Text(
                      statusText,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Settle Up',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            if (provider.pendingSettlements.isEmpty)
              _buildSettledEmptyState(context)
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: provider.pendingSettlements.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final debt = provider.pendingSettlements[i];
                  final fromName = provider.getMemberName(debt.fromMemberId);
                  final toMember = provider.getMember(debt.toMemberId);
                  final toName = toMember?.name ?? 'Squad Member';

                  return _buildCleanSettlementCard(
                    context,
                    fromName: fromName,
                    toName: toName,
                    amount: debt.amount,
                    upiId: toMember?.upiId ?? '',
                    onSettle: () => provider.markDebtSettled(
                        debt.fromMemberId, debt.toMemberId, debt.amount),
                  );
                },
              ),

            const SizedBox(height: 26),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity (Swipe to delete)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                TextButton(
                  onPressed: () => provider.setTabIndex(1),
                  child: Text(
                    'View all',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (provider.expenses.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No expenses recorded yet.'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: math.min(4, provider.expenses.length),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final exp = provider.expenses[i];
                  return Dismissible(
                    key: Key(exp.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.delete_outline_rounded, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Delete',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    onDismissed: (_) {
                      provider.deleteExpense(exp.id);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Deleted "${exp.title}"'),
                          action: SnackBarAction(
                            label: 'UNDO',
                            textColor: AppColors.secondary,
                            onPressed: () => provider.undoDeleteExpense(),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: ExpenseTile(expense: exp),
                  );
                },
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanSettlementCard(
    BuildContext context, {
    required String fromName,
    required String toName,
    required double amount,
    required String upiId,
    required VoidCallback onSettle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    void launchUpiPayment() async {
      if (upiId.isEmpty) {
        onSettle();
        return;
      }
      final upiUri = Uri.parse(
          'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(toName)}&am=$amount&cu=INR');
      if (await canLaunchUrl(upiUri)) {
        await launchUrl(upiUri, mode: LaunchMode.externalApplication);
      }
      onSettle();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    fromName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '➔',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    toName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.formatRupee(amount),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          BouncyButton(
            onTap: launchUpiPayment,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                upiId.isNotEmpty ? 'Pay UPI' : 'Settle',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettledEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Text('🎉', style: TextStyle(fontSize: 28)),
          ),
          const SizedBox(height: 10),
          Text(
            'All settled up!',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Everyone is squared away. No pending debts in the squad!',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMemberButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BouncyButton(
      onTap: () => _showAddMemberDialog(context),
      child: Container(
        width: 78,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              'Add New',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final upiCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Add Squad Member',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Friend Name',
                hintText: 'e.g. Yash',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: upiCtrl,
              decoration: const InputDecoration(
                labelText: 'UPI ID (Optional)',
                hintText: 'e.g. yash@upi',
              ),
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
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                context.read<AppProvider>().addMember(
                      name,
                      upiCtrl.text.trim(),
                    );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Friend'),
          ),
        ],
      ),
    );
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    final categories = ['All', ...AppColors.categoryColors.keys];

    final filteredExpenses = provider.expenses.where((exp) {
      final matchesSearch =
          exp.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              exp.note.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat =
          _selectedCategory == 'All' || exp.category == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Activity Log',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search expenses, canteen treats...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final cat = categories[i];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = cat);
                  },
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? AppColors.textMuted : const Color(0xFF64748B)),
                  ),
                  selectedColor: AppColors.primary,
                  backgroundColor:
                      isDark ? AppColors.darkCard : AppColors.lightSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filteredExpenses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🔍', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(
                          'No matching expenses',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    itemCount: filteredExpenses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final exp = filteredExpenses[i];
                      return Dismissible(
                        key: Key(exp.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.white),
                              SizedBox(width: 6),
                              Text('Delete',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        onDismissed: (_) {
                          provider.deleteExpense(exp.id);
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Deleted "${exp.title}"'),
                              action: SnackBarAction(
                                label: 'UNDO',
                                textColor: AppColors.secondary,
                                onPressed: () => provider.undoDeleteExpense(),
                              ),
                              behavior: SnackBarBehavior.floating,
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

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.lightText;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final catMap = provider.categorySpendMap;
    final total = provider.filteredAnalyticsExpenses
        .fold(0.0, (sum, exp) => sum + exp.amount);

    final List<PieChartSectionData> pieSections = [];
    int colorIdx = 0;
    catMap.forEach((category, amount) {
      final color = AppColors.categoryColors[category] ??
          Colors.primaries[colorIdx % Colors.primaries.length];
      final percentage = total > 0 ? (amount / total) * 100 : 0.0;
      pieSections.add(
        PieChartSectionData(
          color: color,
          value: amount,
          title: '${percentage.toStringAsFixed(0)}%',
          radius: 46,
          titleStyle: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
      colorIdx++;
    });

    String topCategory = 'None';
    double topAmount = 0.0;
    catMap.forEach((k, v) {
      if (v > topAmount) {
        topAmount = v;
        topCategory = k;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Spend Analytics',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<AnalyticsTimeframe>(
              segments: const [
                ButtonSegment(
                    value: AnalyticsTimeframe.week, label: Text('This Week')),
                ButtonSegment(
                    value: AnalyticsTimeframe.month, label: Text('This Month')),
                ButtonSegment(
                    value: AnalyticsTimeframe.allTime,
                    label: Text('All Time')),
              ],
              selected: {provider.analyticsTimeframe},
              onSelectionChanged: (set) =>
                  provider.setAnalyticsTimeframe(set.first),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PERIOD SPEND',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedRupeeCounter(
                          value: total,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOP CATEGORY',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          topCategory,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.secondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Text(
              'Category Breakdown',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderColor),
              ),
              child: catMap.isEmpty
                  ? const SizedBox(
                      height: 180,
                      child: Center(child: Text('No spending in this period')),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 180,
                          child: PieChart(
                            PieChartData(
                              sections: pieSections,
                              centerSpaceRadius: 38,
                              sectionsSpace: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...catMap.entries.map((entry) {
                          final color = AppColors.categoryColors[entry.key] ??
                              AppColors.primary;
                          final pct = total > 0
                              ? (entry.value / total) * 100
                              : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  entry.key,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  Formatters.formatRupee(entry.value),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '(${pct.toStringAsFixed(1)}%)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
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
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings & Preferences',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'APPEARANCE & LOCALE',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      title: Text(
                        'Dark Mode Theme',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        'High contrast OLED dark interface',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                      value: isDark,
                      activeColor: AppColors.primary,
                      onChanged: (_) => provider.toggleTheme(),
                    ),
                  ),
                  Divider(height: 1, color: borderColor),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      title: Text(
                        'Currency Display',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        'Indian Rupee (INR - ₹)',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                      trailing: const Text('🇮🇳 ₹', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'SQUAD MEMBERS (${provider.members.length})',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: provider.members.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                itemBuilder: (ctx, i) {
                  final m = provider.members[i];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Formatters.parseHexColor(m.avatarColor),
                        child: Text(
                          m.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        m.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        m.upiId.isNotEmpty ? m.upiId : 'No UPI added',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'DANGER ZONE',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent),
                  title: Text(
                    'Reset All Expenses',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                    ),
                  ),
                  subtitle: Text(
                    'Clears history and balance calculations',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reset Everything?'),
                        content: const Text(
                            'This will clear all expense records and reset all balances back to zero.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            onPressed: () {
                              provider.resetAllData();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Reset All Data'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class AddExpenseBottomSheet extends StatefulWidget {
  const AddExpenseBottomSheet({super.key});

  @override
  State<AddExpenseBottomSheet> createState() => _AddExpenseBottomSheetState();
}

class _AddExpenseBottomSheetState extends State<AddExpenseBottomSheet> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _selectedCategory = 'Canteen';
  bool _isMultiPayer = false;
  String _singlePayerId = '1';

  SplitMode _splitMode = SplitMode.equal;
  final Set<String> _selectedSplitters = {};

  final Map<String, TextEditingController> _paidCtrls = {};
  final Map<String, TextEditingController> _exactCtrls = {};
  final Map<String, TextEditingController> _percentCtrls = {};

  @override
  void initState() {
    super.initState();
    final members = context.read<AppProvider>().members;
    for (final m in members) {
      _selectedSplitters.add(m.id);
      _paidCtrls[m.id] = TextEditingController(text: '0');
      _exactCtrls[m.id] = TextEditingController(text: '0');
      _percentCtrls[m.id] = TextEditingController(
          text: (100.0 / members.length).toStringAsFixed(1));
    }
  }

  void _recalculateAutoSplits() {
    final rawAmount = double.tryParse(_amountCtrl.text.trim());
    if (rawAmount == null || !rawAmount.isFinite || rawAmount.isNaN || rawAmount <= 0) {
      return;
    }

    if (_selectedSplitters.isEmpty) return;

    final perPerson = rawAmount / _selectedSplitters.length;
    final pctPerson = 100.0 / _selectedSplitters.length;

    for (final id in _selectedSplitters) {
      _exactCtrls[id]?.text = perPerson.toStringAsFixed(2);
      _percentCtrls[id]?.text = pctPerson.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    for (final c in _paidCtrls.values) {
      c.dispose();
    }
    for (final c in _exactCtrls.values) {
      c.dispose();
    }
    for (final c in _percentCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add New Expense',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _amountCtrl,
              onChanged: (_) => _recalculateAutoSplits(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                hintText: '0.00',
                labelText: 'Total Amount',
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Expense Title',
                hintText: 'e.g. Canteen Treat, Auto to Campus',
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note / Description (Optional)',
                hintText: 'e.g. Extra juice included',
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'CATEGORY',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: AppColors.categoryColors.keys.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  final icon = AppColors.categoryIcons[cat] ?? '🏷️';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Row(
                        children: [
                          Text(icon),
                          const SizedBox(width: 4),
                          Text(cat),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                      selectedColor: AppColors.primary,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PAID BY',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Multiple Payers',
                      style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Switch(
                      value: _isMultiPayer,
                      activeColor: AppColors.primary,
                      onChanged: (val) => setState(() => _isMultiPayer = val),
                    ),
                  ],
                ),
              ],
            ),
            if (!_isMultiPayer)
              DropdownButton<String>(
                value: _singlePayerId,
                isExpanded: true,
                items: provider.members.map((m) {
                  return DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      m.name,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _singlePayerId = v);
                },
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
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600))),
                        SizedBox(
                          width: 100,
                          height: 40,
                          child: TextField(
                            controller: _paidCtrls[m.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              prefixText: '₹ ',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),

            SegmentedButton<SplitMode>(
              segments: const [
                ButtonSegment(
                  value: SplitMode.equal,
                  label: Text('Equal (=)'),
                ),
                ButtonSegment(
                  value: SplitMode.exact,
                  label: Text('Exact (₹)'),
                ),
                ButtonSegment(
                  value: SplitMode.percentage,
                  label: Text('Ratio (%)'),
                ),
              ],
              selected: {_splitMode},
              onSelectionChanged: (set) {
                setState(() => _splitMode = set.first);
                _recalculateAutoSplits();
              },
            ),
            const SizedBox(height: 16),

            Text(
              'SPLIT AMONG (${_selectedSplitters.length} Selected)',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),

            Column(
              children: provider.members.map((m) {
                final isSelected = _selectedSplitters.contains(m.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primary,
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
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
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
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: BouncyButton(
                onTap: _saveExpense,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Add & Split Bill',
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

class ExpenseTile extends StatelessWidget {
  final Expense expense;

  const ExpenseTile({super.key, required this.expense});

  void _showExpenseDetails(BuildContext context) {
    final provider = context.read<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? Colors.white : AppColors.lightText;

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
                  color: AppColors.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  AppColors.categoryIcons[expense.category] ?? '🏷️',
                  style: const TextStyle(fontSize: 28),
                ),
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
                          color: AppColors.textMuted,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
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
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'SPLIT ALLOCATION (${expense.splitMode.name.toUpperCase()} MODE)',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
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
                        color: AppColors.secondary,
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
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    final payerNames = expense.paidBy.keys
        .map((id) => provider.getMemberName(id))
        .join(', ');

    final icon = AppColors.categoryIcons[expense.category] ?? '🏷️';
    final color =
        AppColors.categoryColors[expense.category] ?? AppColors.primary;

    return BouncyButton(
      onTap: () => _showExpenseDetails(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 20)),
              ),
            ),
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
                      color: AppColors.textMuted,
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
// 8. ENTRYPOINT
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
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
          secondary: AppColors.secondary,
          surface: AppColors.lightCard,
          onSurface: AppColors.lightText,
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
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.darkCard,
          onSurface: Colors.white,
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
        ),
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