import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_repositories.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/ui/benchmark/max_lift_measurement_page.dart';

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  List<Exercise> exercises = <Exercise>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Exercise> loaded = await AppRepositories.exercises.listExercises();
    if (!mounted) {
      return;
    }
    setState(() {
      exercises = loaded.where((exercise) => !exercise.isDefault).toList();
      isLoading = false;
    });
  }

  String _benchmarkInfo(Exercise exercise) {
    if (!exercise.isSideSwitching) {
      return 'Max lift: ${exercise.maxLiftLeftKg}kg';
    }
    return 'L ${exercise.maxLiftLeftKg}kg  •  R ${exercise.maxLiftRightKg}kg';
  }

  Future<void> _openBenchmark(Exercise exercise) async {
    final Exercise? updated = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (_) => MaxLiftMeasurementPage(exercise: exercise),
      ),
    );

    if (updated == null) {
      return;
    }

    await AppRepositories.exercises.saveExercise(updated);
    await _reload();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved benchmark for ${updated.name}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benchmark'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : exercises.isEmpty
              ? const Center(child: Text('No exercises available for benchmark.'))
              : ListView.separated(
                  itemCount: exercises.length,
                  separatorBuilder: (context, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final Exercise exercise = exercises[index];
                    return ListTile(
                      title: Text(exercise.name),
                      subtitle: Text(_benchmarkInfo(exercise)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openBenchmark(exercise),
                    );
                  },
                ),
    );
  }
}


