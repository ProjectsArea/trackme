import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_trip_detail_screen.dart';

class AdminUserTripsScreen extends StatefulWidget {
  final String userId;
  const AdminUserTripsScreen({super.key, required this.userId});

  @override
  State<AdminUserTripsScreen> createState() => _AdminUserTripsScreenState();
}

class _AdminUserTripsScreenState extends State<AdminUserTripsScreen> {
  Map<String, dynamic>? _user;
  bool _loadingUser = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastNonEmptyDocs = [];
  bool _initialLoaded = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tripSub;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _seedTripsAndSubscribe();
  }

  Future<void> _loadUser() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      _user = snap.data();
    } catch (_) {}
    if (mounted) setState(() => _loadingUser = false);
  }

  void _seedTripsAndSubscribe() {
    // One-time seed to avoid initial empty flicker
    FirebaseFirestore.instance
        .collection('navigation_sessions')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('startedAt', descending: true)
        .get()
        .then((snap) {
      if (!mounted) return;
      setState(() {
        _lastNonEmptyDocs = snap.docs;
        _initialLoaded = true;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _initialLoaded = true);
    });

    // Live updates: keep last non-empty docs to prevent flicker
    _tripSub = FirebaseFirestore.instance
        .collection('navigation_sessions')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('startedAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        if (snap.docs.isNotEmpty) {
          _lastNonEmptyDocs = snap.docs;
        }
        _initialLoaded = true;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _initialLoaded = true);
    });
  }

  @override
  void dispose() {
    _tripSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _user?['employeeName'] ?? 'User';
    final dept = _user?['department'] ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text('Trips - $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E40AF),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF1E40AF).withOpacity(0.1),
                  child: const Icon(Icons.person, color: Color(0xFF1E40AF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      if (dept.toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(dept, style: const TextStyle(color: Colors.blue, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_initialLoaded
                ? const Center(child: CircularProgressIndicator())
                : (_lastNonEmptyDocs.isEmpty
                    ? const Center(child: Text('No trips found'))
                    : _buildList(_lastNonEmptyDocs)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data();
                    final status = (data['status'] ?? 'active') as String;
                    final purpose = (data['purpose'] ?? '') as String;
                    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
                    final endedAt = (data['endedAt'] as Timestamp?)?.toDate();
                    final origin = (data['origin'] ?? {}) as Map<String, dynamic>;
                    final destination = (data['destination'] ?? {}) as Map<String, dynamic>;

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminTripDetailScreen(sessionId: doc.id),
              ),
            );
          },
          child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (status == 'active' ? Colors.green : Colors.grey).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: status == 'active' ? Colors.green : Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (purpose.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      purpose,
                                      style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                const Spacer(),
                                const Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _kvRow('From', origin['address']?.toString() ?? '-', Icons.flag_circle, Colors.green),
                            const SizedBox(height: 6),
                            _kvRow('To', destination['address']?.toString() ?? '-', Icons.place, Colors.red),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 6),
                                Text(
                                  startedAt != null ? _timeAgo(startedAt) : '-',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                ),
                                if (endedAt != null) ...[
                                  const SizedBox(width: 12),
                                  const Icon(Icons.stop_circle_outlined, size: 16, color: Colors.blueGrey),
                                  const SizedBox(width: 6),
                                  Text(
                                    _timeAgo(endedAt),
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
          ),
        );
      },
    );
  }

  Widget _kvRow(String label, String value, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}


