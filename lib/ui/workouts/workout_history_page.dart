import 'package:flutter/material.dart';
import 'package:pullcrane/data/app_stores.dart';
import 'package:pullcrane/domain/models/exercise.dart';
import 'package:pullcrane/domain/models/set_log.dart';
import 'package:pullcrane/domain/models/workout_session.dart';

String formatSessionDate(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key});

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  List<WorkoutSession> sessions = <WorkoutSession>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<WorkoutSession> loaded = await AppStores.sessions.listSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      sessions = loaded;
      isLoading = false;
    });
  }

  Future<void> _openDetail(WorkoutSession session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionDetailPage(sessionId: session.id),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
              ? const Center(child: Text('No sessions recorded yet.'))
              : ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final WorkoutSession session = sessions[index];
                    final Duration duration =
                        session.finishedAt.difference(session.startedAt);
                    return ListTile(
                      leading: Icon(
                        session.completed
                            ? Icons.check_circle_outline
                            : Icons.stop_circle_outlined,
                        color: session.completed
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      title: Text(session.workoutName),
                      subtitle: Text(
                        '${formatSessionDate(session.startedAt)} • '
                        '${session.setCount} sets • ${duration.inMinutes} min',
                      ),
                      onTap: () => _openDetail(session),
                    );
                  },
                ),
    );
  }
}

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  WorkoutSession? session;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final WorkoutSession? loaded =
        await AppStores.sessions.getSession(widget.sessionId);
    if (!mounted) {
      return;
    }
    setState(() {
      session = loaded;
      isLoading = false;
    });
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text('This recorded session will be permanently deleted.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await AppStores.sessions.deleteSession(widget.sessionId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _describeSet(SetLog log) {
    final String plan = log.plannedDurationSeconds > 0
        ? '${log.actualDurationSeconds}/${log.plannedDurationSeconds}s'
        : '${log.plannedReps} reps';
    return '$plan • peak ${log.peakForceKg}kg / target ${log.targetForceKg}kg';
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutSession? loaded = session;
    return Scaffold(
      appBar: AppBar(
        title: Text(loaded?.workoutName ?? 'Session'),
        actions: [
          if (loaded != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete session',
              onPressed: _delete,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loaded == null
              ? const Center(child: Text('Session not found.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${formatSessionDate(loaded.startedAt)} • '
                      '${loaded.completed ? 'Completed' : 'Aborted'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (loaded.setLogs.isEmpty)
                      const Text('No sets were logged in this session.')
                    else
                      ...loaded.setLogs.map(
                        (log) => Card(
                          child: ListTile(
                            title: Text(
                              '${log.exerciseName} — Set ${log.setNumber}'
                              '${log.hand != null ? ' (${log.hand == ExerciseHand.left ? 'Left' : 'Right'})' : ''}',
                            ),
                            subtitle: Text(_describeSet(log)),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
