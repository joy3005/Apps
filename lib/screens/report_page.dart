import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jeyam_dairy/database_helper.dart';
import 'package:jeyam_dairy/theme.dart';
import 'package:intl/intl.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;

  // Toggle State: 7 Days vs 30 Days
  int _selectedDays = 7;

  double _totalMorning = 0;
  double _totalEvening = 0;

  final Color _morningColor = Colors.orange;
  final Color _eveningColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final rawData = await DatabaseHelper.instance.getMilkDataForReport(
      _selectedDays,
    );

    double tM = 0;
    double tE = 0;
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
    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        title: const Text("Production Reports"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 1. TOGGLE BUTTONS (Weekly / Monthly)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  _buildToggleOption("Weekly (7 Days)", 7),
                  Container(width: 1, height: 40, color: Colors.green[200]),
                  _buildToggleOption("Monthly (30 Days)", 30),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              _buildChartCard("Production Share", _buildPieChart()),
              const SizedBox(height: 20),
              _buildChartCard("Daily Performance", _buildBarChart()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleOption(String label, int days) {
    bool isSelected = _selectedDays == days;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (!isSelected) {
            setState(() => _selectedDays = days);
            _fetchData();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.green[100] : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.green[900] : Colors.grey[600],
            ),
          ),
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem("Morning", _morningColor),
                const SizedBox(width: 20),
                _buildLegendItem("Evening", _eveningColor),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(height: 250, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPieChart() {
    if (_totalMorning == 0 && _totalEvening == 0)
      return const Center(child: Text("No Data"));
    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: _totalMorning,
            title: "${_totalMorning.toStringAsFixed(1)} L",
            color: _morningColor,
            radius: 50,
            titleStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            value: _totalEvening,
            title: "${_totalEvening.toStringAsFixed(1)} L",
            color: _eveningColor,
            radius: 60,
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

  Widget _buildBarChart() {
    if (_data.isEmpty) return const Center(child: Text("No Data"));
    Map<String, Map<String, double>> grouped = {};
    for (var row in _data) {
      String date = row['Date'];
      if (!grouped.containsKey(date))
        grouped[date] = {'morning': 0.0, 'evening': 0.0};
      if (row['Time'] == 'Morning')
        grouped[date]!['morning'] =
            (grouped[date]!['morning'] ?? 0) + (row['MorningMilk'] ?? 0);
      else
        grouped[date]!['evening'] =
            (grouped[date]!['evening'] ?? 0) + (row['EveningMilk'] ?? 0);
    }

    List<BarChartGroupData> barGroups = [];
    int index = 0;
    grouped.forEach((date, values) {
      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: values['morning']!,
              color: _morningColor,
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: values['evening']!,
              color: _eveningColor,
              width: 12,
              borderRadius: BorderRadius.circular(4),
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
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}
