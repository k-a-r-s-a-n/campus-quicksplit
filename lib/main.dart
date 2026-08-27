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

// ============================================================================
// 1. PALETTE & DESIGN TOKENS
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
      );
}

class SimplifiedDebt {
  final String fromMemberId;
  final String toMemberId;
  final double amount;
  bool isSettled;

  SimplifiedDebt({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    this.isSettled = false,
  });
}

// ============================================================================
// 3. GREEDY DEBT MINIMIZATION ALGORITHM
// ============================================================================
class DebtOptimizer {
  static List<SimplifiedDebt> computeSimplifiedDebts({
    required List<Member> members,
    required List<Expense> expenses,
    required Set<String> settledKeys,
  }) {
    if (members.isEmpty || expenses.isEmpty) return [];

    final Map<String, double> balances = {for (var m in members) m.id: 0.0};

    for (final exp in expenses) {
      exp.paidBy.forEach((payerId, paidAmount) {
        balances[payerId] = (balances[payerId] ?? 0.0) + paidAmount;
      });

      exp.splits.forEach((borrowerId, owedAmount) {
        balances[borrowerId] = (balances[borrowerId] ?? 0.0) - owedAmount;
      });
    }

    final List<MapEntry<String, double>> debtors = [];
    final List<MapEntry<String, double>> creditors = [];

    balances.forEach((memberId, net) {
      if (net < -0.01) debtors.add(MapEntry(memberId, net));
      if (net > 0.01) creditors.add(MapEntry(memberId, net));
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

      if (roundedTransfer > 0.01) {
        final key = '${debtorId}_to_${creditorId}';
        result.add(
          SimplifiedDebt(
            fromMemberId: debtorId,
            toMemberId: creditorId,
            amount: roundedTransfer,
            isSettled: settledKeys.contains(key),
          ),
        );
      }

      tempBalances[debtorId] = tempBalances[debtorId]! + transferAmount;
      tempBalances[creditorId] = tempBalances[creditorId]! - transferAmount;

      if (tempBalances[debtorId]!.abs() < 0.01) dIdx++;
      if (tempBalances[creditorId]!.abs() < 0.01) cIdx++;
    }

    return result;
  }
}

// ============================================================================
// 4. PROVIDER STATE MANAGEMENT
// ============================================================================
class AppProvider extends ChangeNotifier {
  static const String boxName = 'campus_quicksplit_box';
  late Box _box;

  ThemeMode _themeMode = ThemeMode.dark;
  int _currentTabIndex = 0;

  List<Member> _members = [];
  List<Expense> _expenses = [];
  final Set<String> _settledDebts = {};
  Expense? _recentlyDeletedExpense;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  int get currentTabIndex => _currentTabIndex;
  List<Member> get members => List.unmodifiable(_members);
  List<Expense> get expenses => List.unmodifiable(_expenses);
  Set<String> get settledDebts => Set.unmodifiable(_settledDebts);

  Future<void> init() async {
    _box = await Hive.openBox(boxName);
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final isDarkMode = _box.get('is_dark_mode', defaultValue: true);
    _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;

    final membersRaw = _box.get('members');
    if (membersRaw != null) {
      _members = (jsonDecode(membersRaw) as List)
          .map((e) => Member.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      _members = [
        Member(id: '1', name: 'Aarav (You)', avatarColor: '#6C63FF', upiId: 'aarav@okaxis'),
        Member(id: '2', name: 'Rohan', avatarColor: '#00C896', upiId: 'rohan@oksbi'),
        Member(id: '3', name: 'Priya', avatarColor: '#FF6584', upiId: 'priya@okicici'),
        Member(id: '4', name: 'Kabir', avatarColor: '#FFB84C', upiId: 'kabir@paytm'),
      ];
      _saveMembers();
    }

    final expensesRaw = _box.get('expenses');
    if (expensesRaw != null) {
      _expenses = (jsonDecode(expensesRaw) as List)
          .map((e) => Expense.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
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
          splits: {'1': 120.0, '2': 120.0, '3': 120.0, '4': 120.0},
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
          splits: {'1': 40.0, '2': 40.0, '4': 40.0},
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
          splits: {'1': 62.5, '2': 62.5, '3': 62.5, '4': 62.5},
        ),
      ];
      _saveExpenses();
    }

    final settledRaw = _box.get('settled_debts');
    if (settledRaw != null) {
      _settledDebts.addAll(List<String>.from(jsonDecode(settledRaw)));
    }

    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _box.put('is_dark_mode', _themeMode == ThemeMode.dark);
    notifyListeners();
  }

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  void _saveMembers() {
    _box.put('members', jsonEncode(_members.map((m) => m.toMap()).toList()));
  }

  void _saveExpenses() {
    _box.put('expenses', jsonEncode(_expenses.map((e) => e.toMap()).toList()));
  }

  void _saveSettled() {
    _box.put('settled_debts', jsonEncode(_settledDebts.toList()));
  }

  void addMember(String name, String upiId) {
    final colors = ['#6C63FF', '#00C896', '#FF6584', '#FFB84C', '#38BDF8', '#A78BFA'];
    final randomColor = colors[_members.length % colors.length];
    final member = Member(
      id: const Uuid().v4(),
      name: name.trim(),
      avatarColor: randomColor,
      upiId: upiId.trim(),
    );
    _members.add(member);
    _saveMembers();
    notifyListeners();
  }

  void addExpense(Expense expense) {
    _expenses.insert(0, expense);
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
      _expenses.insert(0, _recentlyDeletedExpense!);
      _recentlyDeletedExpense = null;
      _saveExpenses();
      notifyListeners();
    }
  }

  void markDebtSettled(String fromId, String toId, double amount) {
    final key = '${fromId}_to_${toId}';
    _settledDebts.add(key);
    _saveSettled();

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
    );
    _expenses.insert(0, settlementExpense);
    _saveExpenses();

    notifyListeners();
  }

  void resetAllData() {
    _expenses.clear();
    _settledDebts.clear();
    _saveExpenses();
    _saveSettled();
    notifyListeners();
  }

  String getMemberName(String id) {
    final member = _members.firstWhere(
      (m) => m.id == id,
      orElse: () => Member(id: id, name: 'Squad Member', avatarColor: '#6C63FF'),
    );
    return member.name;
  }

  double get totalGroupSpend =>
      _expenses.fold(0.0, (sum, item) => sum + item.amount);

  double get myTotalPaid => _expenses.fold(0.0, (sum, item) {
        return sum + (item.paidBy['1'] ?? 0.0);
      });

  double get myTotalOwed => _expenses.fold(0.0, (sum, item) {
        return sum + (item.splits['1'] ?? 0.0);
      });

  double get myNetBalance => myTotalPaid - myTotalOwed;

  List<SimplifiedDebt> get pendingSettlements {
    final debts = DebtOptimizer.computeSimplifiedDebts(
      members: _members,
      expenses: _expenses,
      settledKeys: _settledDebts,
    );
    return debts.where((d) => !d.isSettled).toList();
  }

  Map<String, double> get categorySpendMap {
    final map = <String, double>{};
    for (final exp in _expenses) {
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

  static String formatShortDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${math.max(1, diff.inMinutes)}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('dd MMM').format(dt);
    }
  }

  static Color parseHexColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

// ============================================================================
// 6. CUSTOM INTERACTIVE WIDGETS
// ============================================================================

class Matrix4TiltCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final Border? border;
  final double borderRadius;

  const Matrix4TiltCard({
    super.key,
    required this.child,
    this.onTap,
    this.gradient,
    this.color,
    this.border,
    this.borderRadius = 24.0,
  });

  @override
  State<Matrix4TiltCard> createState() => _Matrix4TiltCardState();
}

class _Matrix4TiltCardState extends State<Matrix4TiltCard>
    with SingleTickerProviderStateMixin {
  double _x = 0;
  double _y = 0;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _onPointerMove(PointerEvent event, BoxConstraints constraints) {
    final centerX = constraints.maxWidth / 2;
    final centerY = constraints.maxHeight / 2;
    final deltaX = (event.localPosition.dx - centerX) / centerX;
    final deltaY = (event.localPosition.dy - centerY) / centerY;

    setState(() {
      _x = deltaY * -0.06;
      _y = deltaX * 0.06;
    });
  }

  void _onPointerExit(PointerEvent event) {
    _animController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _x = 0;
          _y = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (e) => _onPointerMove(e, constraints),
          onExit: _onPointerExit,
          child: Listener(
            onPointerMove: (e) => _onPointerMove(e, constraints),
            onPointerUp: _onPointerExit,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(_x)
                  ..rotateY(_y),
                alignment: FractionalOffset.center,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: widget.gradient,
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: widget.border,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SymmetricalNotchedBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onFabTap;

  const SymmetricalNotchedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onFabTap,
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
    final inactiveColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textMuted
        : const Color(0xFF64748B);

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
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

  @override
  void initState() {
    super.initState();
    _startTypewriter();
  }

  void _startTypewriter() async {
    while (_charIndex < _fullTitle.length) {
      await Future.delayed(const Duration(milliseconds: 55));
      if (!mounted) return;
      setState(() {
        _charIndex++;
        _typedTitle = _fullTitle.substring(0, _charIndex);
      });
    }

    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    setState(() => _showTagline = true);

    await Future.delayed(const Duration(milliseconds: 900));
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(
                child: Text('⚡', style: TextStyle(fontSize: 38)),
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
      body: IndexedStack(
        index: provider.currentTabIndex,
        children: screens,
      ),
      bottomNavigationBar: SymmetricalNotchedBottomNav(
        currentIndex: provider.currentTabIndex,
        onTap: (index) => provider.setTabIndex(index),
        onFabTap: () => _openAddExpenseModal(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        height: 56,
        width: 56,
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
              color: AppColors.primary.withOpacity(0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _openAddExpenseModal(context),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
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
    final textColor = isDark ? Colors.white : AppColors.lightText;

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
            Matrix4TiltCard(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                            fontSize: 12,
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
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Campus Group',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      Formatters.formatRupee(provider.myNetBalance),
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
                                Text(
                                  Formatters.formatRupee(
                                      math.max(0.0, provider.myNetBalance)),
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
                                Text(
                                  Formatters.formatRupee(
                                      math.max(0.0, -provider.myNetBalance)),
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

            const SizedBox(height: 26),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Squad Members',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${provider.members.length} friends',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: provider.members.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  if (i == provider.members.length) {
                    return _buildAddMemberButton(context);
                  }
                  final member = provider.members[i];
                  return _buildMemberPill(context, member);
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
                  final toName = provider.getMemberName(debt.toMemberId);

                  return _buildCleanSettlementCard(
                    context,
                    fromName: fromName,
                    toName: toName,
                    amount: debt.amount,
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
                  'Recent Activity',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
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
                  return ExpenseTile(expense: exp);
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
    required VoidCallback onSettle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

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
          ElevatedButton(
            onPressed: onSettle,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Mark Settled'),
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

  Widget _buildMemberPill(BuildContext context, Member member) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Formatters.parseHexColor(member.avatarColor),
            child: Text(
              member.name.substring(0, 1).toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              member.name.split(' ').first,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMemberButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => _showAddMemberDialog(context),
      borderRadius: BorderRadius.circular(16),
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
              if (nameCtrl.text.trim().isNotEmpty) {
                context.read<AppProvider>().addMember(
                      nameCtrl.text.trim(),
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
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (direction) {
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
    final total = provider.totalGroupSpend;

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
                          'TOTAL GROUP SPEND',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Formatters.formatRupee(total),
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
                          'YOUR TOTAL PAID',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Formatters.formatRupee(provider.myTotalPaid),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.success,
                          ),
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
                      child: Center(child: Text('No spending data to graph')),
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

// ----------------------------------------------------------------------------
// G. ENHANCED ADD EXPENSE BOTTOM SHEET MODAL (With Multi-Payer + Exact/Ratio Inputs)
// ----------------------------------------------------------------------------
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                      selectedColor: AppColors.primary,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Multi-Payer Toggle Section
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

            // Split Mode Segmented Button
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
              onSelectionChanged: (set) =>
                  setState(() => _splitMode = set.first),
            ),
            const SizedBox(height: 16),

            Text(
              'SPLIT AMONG',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),

            // Split Members List with Inline Fields for Exact/Percentage
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
              child: ElevatedButton(
                onPressed: _saveExpense,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Add & Split Bill'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveExpense() {
    final title = _titleCtrl.text.trim();
    final totalAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    if (title.isEmpty || totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid title and amount greater than ₹0')),
      );
      return;
    }

    if (_selectedSplitters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 person to split')),
      );
      return;
    }

    // Process Payers Map
    final Map<String, double> finalPaidBy = {};
    if (!_isMultiPayer) {
      finalPaidBy[_singlePayerId] = totalAmount;
    } else {
      double sumPaid = 0.0;
      _paidCtrls.forEach((id, ctrl) {
        final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
        if (val > 0) {
          finalPaidBy[id] = val;
          sumPaid += val;
        }
      });
      if ((sumPaid - totalAmount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Multi-payer total (₹$sumPaid) must equal total expense (₹$totalAmount)')),
        );
        return;
      }
    }

    // Process Splits Map
    final Map<String, double> finalSplits = {};

    if (_splitMode == SplitMode.equal) {
      final perPerson = totalAmount / _selectedSplitters.length;
      final roundedPerPerson = (perPerson * 100).round() / 100.0;
      for (final id in _selectedSplitters) {
        finalSplits[id] = roundedPerPerson;
      }
    } else if (_splitMode == SplitMode.exact) {
      double sumExact = 0.0;
      for (final id in _selectedSplitters) {
        final val = double.tryParse(_exactCtrls[id]?.text ?? '0') ?? 0.0;
        finalSplits[id] = val;
        sumExact += val;
      }
      if ((sumExact - totalAmount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Sum of exact splits (₹$sumExact) must equal total amount (₹$totalAmount)')),
        );
        return;
      }
    } else {
      double sumPct = 0.0;
      for (final id in _selectedSplitters) {
        final pct = double.tryParse(_percentCtrls[id]?.text ?? '0') ?? 0.0;
        sumPct += pct;
        finalSplits[id] = (totalAmount * pct) / 100.0;
      }
      if ((sumPct - 100.0).abs() > 0.5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Total percentage sum ($sumPct%) must equal 100%')),
        );
        return;
      }
    }

    final expense = Expense(
      id: const Uuid().v4(),
      title: title,
      amount: totalAmount,
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? Colors.white : AppColors.lightText;

    final payerId = expense.paidBy.keys.isNotEmpty
        ? expense.paidBy.keys.first
        : '1';
    final payerName = provider.getMemberName(payerId);
    final icon = AppColors.categoryIcons[expense.category] ?? '🏷️';
    final color =
        AppColors.categoryColors[expense.category] ?? AppColors.primary;

    return Container(
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
                  'Paid by $payerName • ${Formatters.formatShortDate(expense.date)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
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
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 8. MAIN ROOT WIDGET
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