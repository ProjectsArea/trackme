import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'visit_feedback_form_screen.dart';

class VisitFeedbackListScreen extends StatefulWidget {
  const VisitFeedbackListScreen({super.key});

  @override
  State<VisitFeedbackListScreen> createState() => _VisitFeedbackListScreenState();
}

class _VisitFeedbackListScreenState extends State<VisitFeedbackListScreen> {
  DocumentSnapshot? _lastDoc;
  bool _loadingMore = false;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedDocs = [];

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF1E40AF);
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit Feedback', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const VisitFeedbackFormScreen()),
          );
          if (ok == true && mounted) {
            setState(() {
              _lastDoc = null;
              _cachedDocs.clear();
            });
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('Login required'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('visit_feedback')
                  .where('userId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && _cachedDocs.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasData) {
                  _cachedDocs
                    ..clear()
                    ..addAll(snapshot.data!.docs);
                }
                if (_cachedDocs.isEmpty) {
                  return _emptyState(primary);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _cachedDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = _cachedDocs[index];
                    final data = doc.data();
                    final title = (data['title'] ?? '') as String;
                    final comments = (data['comments'] ?? '') as String;
                    final rating = (data['rating'] ?? 0) as int;
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                    return _feedbackCard(primary, title, comments, rating, createdAt);
                  },
                );
              },
            ),
    );
  }

  Widget _emptyState(Color primary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.rate_review, color:Color.fromRGBO(10, 20, 2, 4), size: 40),
          ),
          const SizedBox(height: 12),
          Text('No feedback yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Tap the + button to add your first feedback', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _feedbackCard(Color primary, String title, String comments, int rating, DateTime? createdAt) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 6))],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title.isEmpty ? 'Untitled' : title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1F2937))),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      Icon(i <= rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 18),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comments, style: TextStyle(color: Colors.grey.shade700, height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text(
                  createdAt != null ? createdAt.toString() : '-',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


