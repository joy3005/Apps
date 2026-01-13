import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jeyam_dairy/database_helper.dart';
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

  // New: For "Current Day" Display
  double _currentMorning = 0;
  double _currentEvening = 0;
  String _dateRangeText = "";

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

    // Find Date Range
    if (rawData.isNotEmpty) {
      DateTime start = DateTime.parse(rawData.first['Date']);
      DateTime end = DateTime.parse(rawData.last['Date']);
      _dateRangeText =
          "${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)}";

      // Get "Current" (Latest) Day Production
      var lastRow = rawData.last;
      // Note: If you have separate rows for Morning/Evening per day,
      // you might need to sum the last 2 rows if they share the same date.
      // Assuming the list is ordered by Date, we check the last date.
      String lastDate = lastRow['Date'];

      double curM = 0;
      double curE = 0;

      // Look at all rows with the same "last date" (could be 1 or 2 rows)
      for (var row in rawData.where((r) => r['Date'] == lastDate)) {
        curM += row['MorningMilk'] ?? 0;
        curE += row['EveningMilk'] ?? 0;
      }
      _currentMorning = curM;
      _currentEvening = curE;
    } else {
      _dateRangeText = "No Data";
      _currentMorning = 0;
      _currentEvening = 0;
    }

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
            // 1. TOGGLE BUTTONS
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  _buildToggleOption("Weekly", 7),
                  Container(width: 1, height: 40, color: Colors.green[200]),
                  _buildToggleOption("Monthly", 30),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // 2. PIE CHART CARD (With Date Range & Current Stats)
              _buildPieChartCard(),

              const SizedBox(height: 20),

              // 3. BAR CHART CARD
              _buildBarChartCard(),
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

  // --- PIE CHART SECTION ---
  Widget _buildPieChartCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Production Share",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _dateRangeText,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                // Pie Chart
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 150,
                    child: (_totalMorning == 0 && _totalEvening == 0)
                        ? const Center(child: Text("No Data"))
                        : PieChart(
                            PieChartData(
                              sections: [
                                PieChartSectionData(
                                  value: _totalMorning,
                                  title: "${_totalMorning.toStringAsFixed(0)}",
                                  color: _morningColor,
                                  radius: 45,
                                  titleStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                PieChartSectionData(
                                  value: _totalEvening,
                                  title: "${_totalEvening.toStringAsFixed(0)}",
                                  color: _eveningColor,
                                  radius: 50,
                                  titleStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              centerSpaceRadius: 30,
                              sectionsSpace: 2,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 20),
                // Legend & Current Stats
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem("Morning", _morningColor),
                      const SizedBox(height: 5),
                      _buildLegendItem("Evening", _eveningColor),
                      const Divider(height: 20),
                      const Text(
                        "Latest Day:",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "M: ${_currentMorning.toStringAsFixed(1)} L",
                        style: TextStyle(color: _morningColor, fontSize: 12),
                      ),
                      Text(
                        "E: ${_currentEvening.toStringAsFixed(1)} L",
                        style: TextStyle(color: _eveningColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // --- BAR CHART SECTION ---
  Widget _buildBarChartCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Daily Performance",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              height: 300,
              child: _data.isEmpty
                  ? const Center(child: Text("No Data"))
                  : _buildBarChart(),
            ),

            // "Days" Label for Monthly View
            if (_selectedDays == 30)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  "Days",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    // 1. Group Data by Date
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

    // 2. Create Bars & Find Max Value
    List<BarChartGroupData> barGroups = [];
    double trueMaxY = 0; // The actual highest milk value
    int index = 0;

    grouped.forEach((date, values) {
      double m = values['morning']!;
      double e = values['evening']!;
      if (m > trueMaxY) trueMaxY = m;
      if (e > trueMaxY) trueMaxY = e;

      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: m,
              color: _morningColor,
              width: _selectedDays == 7 ? 16 : 8,
              borderRadius: BorderRadius.circular(2),
            ),
            BarChartRodData(
              toY: e,
              color: _eveningColor,
              width: _selectedDays == 7 ? 16 : 8,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      );
      index++;
    });

    // 3. CALCULATE "NICE" ROUNDED MAX Y
    // Example: If max is 382, we want 400. If max is 12, we want 15 or 20.
    double interval = 5; // Default step
    if (trueMaxY > 200)
      interval = 50; // Step 0, 50, 100, 150...
    else if (trueMaxY > 100)
      interval = 25; // Step 0, 25, 50, 75...
    else if (trueMaxY > 20)
      interval = 10; // Step 0, 10, 20, 30...
    else
      interval = 5; // Step 0, 5, 10, 15...

    // Add buffer (1.1x) and round up to next interval
    double bufferedMax = trueMaxY * 1;
    double roundedMaxY = ((bufferedMax / interval).ceil() * interval)
        .toDouble();
    if (roundedMaxY == 0) roundedMaxY = 10; // Prevent 0-height chart

    return BarChart(
      BarChartData(
        maxY: roundedMaxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Colors.blueGrey,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              String time = rodIndex == 0 ? "Morning" : "Evening";
              return BarTooltipItem(
                "$time\n${rod.toY.toStringAsFixed(2)} L",
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          // Y-AXIS (LEFT)
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              interval:
                  interval, // <--- This forces the "nice" steps (e.g. 50, 100, 150)
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox();
                // Show simple integers (e.g. 150, 200)
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          // X-AXIS (BOTTOM)
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: _selectedDays == 30 ? 5 : 1,
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                String text = (_selectedDays == 7)
                    ? "Day ${idx + 1}"
                    : "${idx + 1}";
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          // Force grid lines to match our nice intervals
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey[300], strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }
}
