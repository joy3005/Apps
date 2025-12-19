import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jeyam_dairy/database_helper.dart';
import 'package:jeyam_dairy/theme.dart';
import 'package:intl/intl.dart';

class ReportPage extends StatefulWidget {
  final bool isWeekly; // true = 7 days, false = 30 days

  const ReportPage({super.key, required this.isWeekly});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;

  // Aggregate Data
  double _totalMorning = 0;
  double _totalEvening = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    int days = widget.isWeekly ? 7 : 30;
    final rawData = await DatabaseHelper.instance.getMilkDataForReport(days);

    double tM = 0;
    double tE = 0;

    // Aggregate totals
    for (var row in rawData) {
      tM += row['MorningMilk'] ?? 0;
      tE += row['EveningMilk'] ?? 0;
    }

    setState(() {
      _data = rawData;
      _totalMorning = tM;
      _totalEvening = tE;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.isWeekly
        ? "Weekly Report (7 Days)"
        : "Monthly Report (30 Days)";

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 1. PIE CHART SECTION
                  _buildChartCard("Production Share", _buildPieChart()),

                  const SizedBox(height: 20),

                  // 2. BAR CHART SECTION
                  _buildChartCard(
                    "Daily Performance (Side-by-Side)",
                    _buildBarChart(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildChartCard(String title, Widget chart) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.emeraldGreen,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(height: 250, child: chart), // Fixed height for charts
          ],
        ),
      ),
    );
  }

  // --- PIE CHART LOGIC ---
  Widget _buildPieChart() {
    if (_totalMorning == 0 && _totalEvening == 0)
      return const Center(child: Text("No Data"));

    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: _totalMorning,
            title: "${_totalMorning.toStringAsFixed(1)} L",
            color: Colors.orangeAccent,
            radius: 50,
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            value: _totalEvening,
            title: "${_totalEvening.toStringAsFixed(1)} L",
            color: AppTheme.emeraldGreen,
            radius: 60, // Make one slightly larger for style
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  // --- BAR CHART LOGIC ---
  Widget _buildBarChart() {
    if (_data.isEmpty) return const Center(child: Text("No Data"));

    // We need to group data by DATE.
    // Map key: "2025-10-10", Value: {morning: 10, evening: 12}
    Map<String, Map<String, double>> grouped = {};

    for (var row in _data) {
      String date = row['Date'];
      if (!grouped.containsKey(date)) {
        grouped[date] = {'morning': 0.0, 'evening': 0.0};
      }
      if (row['Time'] == 'Morning') {
        grouped[date]!['morning'] =
            (grouped[date]!['morning'] ?? 0) + (row['MorningMilk'] ?? 0);
      } else {
        grouped[date]!['evening'] =
            (grouped[date]!['evening'] ?? 0) + (row['EveningMilk'] ?? 0);
      }
    }

    List<BarChartGroupData> barGroups = [];
    int index = 0;

    grouped.forEach((date, values) {
      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            // Morning Bar
            BarChartRodData(
              toY: values['morning']!,
              color: Colors.orangeAccent,
              width: 12,
            ),
            // Evening Bar
            BarChartRodData(
              toY: values['evening']!,
              color: AppTheme.emeraldGreen,
              width: 12,
            ),
          ],
        ),
      );
      index++;
    });

    return BarChart(
      BarChartData(
        barGroups: barGroups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ), // Hide dates to avoid clutter
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}
