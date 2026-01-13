import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jeyam_dairy/database_helper.dart';

class CowMetricsPage extends StatefulWidget {
  final Map<String, dynamic> cowData;
  const CowMetricsPage({super.key, required this.cowData});

  @override
  State<CowMetricsPage> createState() => _CowMetricsPageState();
}

class _CowMetricsPageState extends State<CowMetricsPage> {
  Map<String, dynamic>? _metrics;
  Map<String, List<Map<String, dynamic>>>? _graphData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    int id = widget.cowData['CowID'];
    int cycle = widget.cowData['CurrentMilkingCycle'];

    // 1. Load Card Metrics
    final metrics = await DatabaseHelper.instance.getCowInsights(id, cycle);

    // 2. Load History Graphs
    final graphs = await DatabaseHelper.instance.getCowHistoryMetrics(id);

    if (mounted) {
      setState(() {
        _metrics = metrics;
        _graphData = graphs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.cowData;
    String? imagePath = c['CowPicturePath'];

    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        title: Text("Metrics: Cow #${c['RFID']}"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 1. HEADER
                  _buildCowHeader(imagePath, c['RFID']),
                  const SizedBox(height: 20),

                  // 2. CURRENT STATS
                  _buildSectionTitle(
                    "Current Cycle (Cycle ${c['CurrentMilkingCycle']})",
                  ),
                  _buildCurrentCycleGrid(),
                  const SizedBox(height: 20),

                  // 3. HISTORY GRAPHS
                  _buildSectionTitle("Historical Analysis"),
                  const SizedBox(height: 10),

                  // A. MILK PRODUCTION
                  _buildGraphTile(
                    "Avg Milk Production (Per Cycle)",
                    _graphData!['milk']!,
                    Colors.blue,
                    "Liters",
                  ),

                  // B. DRY DAYS
                  _buildGraphTile(
                    "Dry Days (Between Cycles)",
                    _graphData!['dry']!,
                    Colors.brown,
                    "Days",
                  ),

                  // C. GESTATION (With Static Injection Labels)
                  _buildGraphTile(
                    "Gestation Period (Injection to Birth)",
                    _graphData!['gestation']!,
                    Colors.purple,
                    "Days",
                    showInjectionLabels: true, // <--- ENABLE STATIC LABELS
                  ),
                ],
              ),
            ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildGraphTile(
    String title,
    List<Map<String, dynamic>> data,
    Color color,
    String unit, {
    bool showInjectionLabels = false,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.bar_chart, color: color),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green[900],
          ),
        ),
        children: [
          Container(
            height: 250,
            padding: const EdgeInsets.fromLTRB(16, 32, 24, 16),
            child: data.isEmpty
                ? const Center(child: Text("Not enough data history."))
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      // Add extra headroom if labels are shown on top
                      maxY: _getMaxY(data) * (showInjectionLabels ? 1 : 1),

                      barTouchData: BarTouchData(
                        // Disable touch for Gestation graph (since we show labels statically)
                        // enabled: !showInjectionLabels,
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipHorizontalAlignment:
                              FLHorizontalAlignment.right,

                          // 2. PREVENT CLIPPING (Keeps it visible if bar is too tall)
                          fitInsideVertically: true,
                          fitInsideHorizontally: true,
                          getTooltipColor: (group) => Colors.blueGrey,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              "${rod.toY.toStringAsFixed(1)} $unit",
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
                        // 1. TOP TITLES (used for Injection Labels)
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles:
                                showInjectionLabels, // Only show if enabled
                            reservedSize: 20,
                            getTitlesWidget: (value, meta) {
                              if (!showInjectionLabels) return const SizedBox();

                              // Find the data point for this Cycle (x-value)
                              int cycleNum = value.toInt();
                              var match = data.firstWhere(
                                (e) => e['x'] == cycleNum,
                                orElse: () => <String, dynamic>{},
                              );

                              if (match.isEmpty || !match.containsKey('meta')) {
                                return const SizedBox();
                              }

                              int count = match['meta'];
                              return Text(
                                "$count Inj",
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                        ),
                        // 2. BOTTOM TITLES (Cycle Number)
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  "Cycle ${value.toInt()}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // 3. LEFT TITLES (Values)
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      // BUILD BARS
                      barGroups: data.map((point) {
                        return BarChartGroupData(
                          x: point['x'] as int,
                          barRods: [
                            BarChartRodData(
                              toY: (point['y'] as num).toDouble(),
                              color: color,
                              width: 20,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  double _getMaxY(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 10;
    double max = 0;
    for (var item in data) {
      double val = (item['y'] as num).toDouble();
      if (val > max) max = val;
    }
    return max;
  }

  // --- HEADER & GRID WIDGETS (UNCHANGED) ---

  Widget _buildCowHeader(String? path, String rfid) {
    bool hasImage = path != null && path.isNotEmpty && File(path).existsSync();
    return Center(
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green[800]!, width: 4),
              image: hasImage
                  ? DecorationImage(
                      image: FileImage(File(path)),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: Colors.white,
            ),
            child: !hasImage
                ? const Icon(Icons.cruelty_free, size: 50, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            "RFID: $rfid",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.green[800],
        ),
      ),
    );
  }

  Widget _buildCurrentCycleGrid() {
    var curr = _metrics!['Current'] ?? {};
    double avg = curr['AvgMilk'] ?? 0.0;
    double max = curr['MaxMilk'] ?? 0.0;
    double min = curr['MinMilk'] ?? 0.0;
    int days = curr['DaysMilked'] ?? 0;

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      childAspectRatio: 2.2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricCard(
          "Avg Milk",
          "${avg.toStringAsFixed(1)} L",
          Colors.blue,
        ),
        _buildMetricCard(
          "Highest",
          "${max.toStringAsFixed(1)} L",
          Colors.green,
        ),
        _buildMetricCard(
          "Lowest",
          "${min.toStringAsFixed(1)} L",
          Colors.orange,
        ),
        _buildMetricCard("Days in Milk", "$days Days", Colors.purple),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
